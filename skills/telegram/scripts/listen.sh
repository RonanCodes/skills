#!/usr/bin/env bash
# telegram/scripts/listen.sh
#
# Long-poll Telegram getUpdates. For each incoming message from TELEGRAM_CHAT_ID:
#   - If message is /new or /reset: rotate the session UUID, ack.
#   - If message is /cwd: reply with current working dir.
#   - If message starts with !: run the rest as raw shell, reply with output.
#   - Otherwise: run `claude -p --session-id <uuid> "<msg>"` in TELEGRAM_LISTEN_CWD
#     and reply with the output.
#
# Conversational continuity is achieved by reusing the same --session-id across
# messages. The state lives in ~/.claude/telegram-session.json. Rotates on /new
# or after TELEGRAM_SESSION_IDLE_HOURS of silence (default 6).
#
# SECURITY: messages from any chat_id other than TELEGRAM_CHAT_ID are dropped.
#
# Subcommands:
#   listen.sh               # foreground
#   listen.sh --cwd PATH    # override TELEGRAM_LISTEN_CWD for this run
#   listen.sh --daemon      # install + load launchd plist (macOS)
#   listen.sh --stop        # unload + remove launchd plist

set -euo pipefail

ENV_FILE="${TELEGRAM_ENV_FILE:-$HOME/.claude/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${TELEGRAM_STATE_FILE:-$HOME/.claude/telegram-session.json}"
OFFSET_FILE="${TELEGRAM_OFFSET_FILE:-$HOME/.claude/telegram-offset}"
IDLE_HOURS="${TELEGRAM_SESSION_IDLE_HOURS:-6}"

PLIST_LABEL="dev.ronanconnolly.telegram-listener"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
DAEMON_LOG="$HOME/Library/Logs/telegram-listener.log"

usage() {
  cat <<'USAGE' >&2
Usage:
  listen.sh [--cwd PATH]   # foreground listener
  listen.sh --daemon       # install + start launchd daemon (macOS)
  listen.sh --stop         # stop + uninstall launchd daemon

The listener requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in ~/.claude/.env
(run scripts/setup.sh first). Optional env:
  TELEGRAM_LISTEN_CWD          working dir for `claude -p` (default $HOME/Dev)
  TELEGRAM_SESSION_IDLE_HOURS  idle gap that triggers a fresh session (default 6)
USAGE
}

# ---------- daemon install / stop ----------

install_daemon() {
  : "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set; run scripts/setup.sh first}"
  : "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID not set; run scripts/setup.sh first}"

  mkdir -p "$(dirname "$PLIST_PATH")"
  mkdir -p "$(dirname "$DAEMON_LOG")"

  # Find claude binary, since launchd has a minimal PATH
  local claude_bin
  claude_bin="$(command -v claude || true)"
  [[ -z "$claude_bin" ]] && { echo "error: 'claude' not on PATH; cannot daemonize" >&2; exit 1; }

  local claude_dir
  claude_dir="$(dirname "$claude_bin")"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${SCRIPT_DIR}/listen.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${DAEMON_LOG}</string>
  <key>StandardErrorPath</key><string>${DAEMON_LOG}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>${claude_dir}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key><string>${HOME}</string>
  </dict>
</dict>
</plist>
PLIST

  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load -w "$PLIST_PATH"

  echo "Daemon installed and started."
  echo "  plist: ${PLIST_PATH}"
  echo "  log:   ${DAEMON_LOG}"
  echo
  echo "Tail the log:"
  echo "  tail -f ${DAEMON_LOG}"
  echo
  echo "Stop it:"
  echo "  bash ${SCRIPT_DIR}/listen.sh --stop"
}

stop_daemon() {
  if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Daemon stopped and plist removed."
  else
    echo "No daemon plist at $PLIST_PATH; nothing to stop."
  fi
}

# ---------- session-state helpers ----------

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

new_session_state() {
  local uuid
  uuid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  cat > "$STATE_FILE" <<JSON
{
  "session_id": "${uuid}",
  "started_at": "$(now_iso)",
  "last_message_at": "$(now_iso)",
  "message_count": 0
}
JSON
  echo "$uuid"
}

current_session_id() {
  if [[ ! -f "$STATE_FILE" ]]; then
    new_session_state
    return
  fi

  python3 - "$STATE_FILE" "$IDLE_HOURS" <<'PY'
import json, os, sys, uuid, datetime as dt
state_path, idle_hours = sys.argv[1], float(sys.argv[2])
with open(state_path) as f:
    s = json.load(f)
last = dt.datetime.strptime(s["last_message_at"], "%Y-%m-%dT%H:%M:%SZ")
gap_h = (dt.datetime.utcnow() - last).total_seconds() / 3600.0
if gap_h > idle_hours:
    s = {
        "session_id": str(uuid.uuid4()),
        "started_at": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "last_message_at": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "message_count": 0,
    }
    with open(state_path, "w") as f:
        json.dump(s, f, indent=2)
print(s["session_id"])
PY
}

bump_session_state() {
  python3 - "$STATE_FILE" <<'PY'
import json, sys, datetime as dt
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s["last_message_at"] = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
s["message_count"] = int(s.get("message_count", 0)) + 1
with open(path, "w") as f:
    json.dump(s, f, indent=2)
PY
}

rotate_session() {
  new_session_state
}

# ---------- send helpers ----------

reply_text() {
  local text="$1" reply_to="$2"
  if [[ -n "$reply_to" ]]; then
    bash "${SCRIPT_DIR}/send.sh" "$text" --reply-to "$reply_to" || true
  else
    bash "${SCRIPT_DIR}/send.sh" "$text" || true
  fi
}

# ---------- main listen loop ----------

run_listener() {
  : "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set; run scripts/setup.sh first}"
  : "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID not set; run scripts/setup.sh first}"

  local cwd="${TELEGRAM_LISTEN_CWD:-$HOME/Dev}"
  [[ -n "${CWD_OVERRIDE:-}" ]] && cwd="$CWD_OVERRIDE"
  [[ -d "$cwd" ]] || { echo "error: cwd '$cwd' does not exist" >&2; exit 1; }

  mkdir -p "$(dirname "$STATE_FILE")"

  local offset
  offset="$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)"

  echo "telegram listener up - cwd=$cwd  chat_id=$TELEGRAM_CHAT_ID  idle_h=$IDLE_HOURS"
  echo "state: $STATE_FILE"

  while true; do
    local resp
    resp="$(curl --silent --show-error --fail \
      --max-time 35 \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?timeout=30&offset=${offset}" \
      || true)"

    if [[ -z "$resp" ]]; then
      sleep 2
      continue
    fi

    # Parse updates one per line: "<update_id>\t<chat_id>\t<message_id>\t<text>"
    local parsed
    parsed="$(printf '%s' "$resp" | python3 <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for u in data.get("result", []):
    msg = u.get("message") or u.get("edited_message")
    if not msg: continue
    chat_id = msg.get("chat", {}).get("id")
    mid = msg.get("message_id")
    text = (msg.get("text") or "").replace("\t", " ").replace("\n", "\\n")
    print(f"{u['update_id']}\t{chat_id}\t{mid}\t{text}")
PY
)"

    if [[ -z "$parsed" ]]; then
      sleep 1
      continue
    fi

    while IFS=$'\t' read -r upd_id from_chat msg_id text; do
      [[ -z "$upd_id" ]] && continue
      offset=$(( upd_id + 1 ))
      echo "$offset" > "$OFFSET_FILE"

      if [[ "$from_chat" != "$TELEGRAM_CHAT_ID" ]]; then
        echo "dropped message from chat_id=$from_chat (not authorized)"
        continue
      fi

      # Unescape newlines we encoded above
      text="${text//\\n/$'\n'}"

      echo ">>> [$(date +%H:%M:%S)] $text"

      # Command routing
      case "$text" in
        /new|/reset)
          local new_uuid
          new_uuid="$(rotate_session)"
          reply_text "new session started: ${new_uuid:0:8}" "$msg_id"
          continue
          ;;
        /cwd)
          reply_text "cwd: $cwd" "$msg_id"
          continue
          ;;
        /help)
          reply_text $'commands:\n/new - rotate session\n/cwd - show working dir\n!<cmd> - run raw shell\n<anything else> - dispatch to claude -p' "$msg_id"
          continue
          ;;
      esac

      # Raw shell escape: leading !
      if [[ "$text" == !* ]]; then
        local sh_cmd="${text:1}"
        local out
        out="$(cd "$cwd" && bash -lc "$sh_cmd" 2>&1 || true)"
        [[ -z "$out" ]] && out="(no output)"
        reply_text "$out" "$msg_id"
        bump_session_state
        continue
      fi

      # Default dispatch: claude -p with shared session id
      local session_id
      session_id="$(current_session_id)"

      # --dangerously-skip-permissions is required for headless launchd context:
      # claude -p has no TTY to prompt for tool-call approvals, so without this
      # flag every Read / Bash / Edit call hangs or errors. Guarded by the strict
      # chat_id allowlist above. To make the bot read-only, remove this flag and
      # rely on whatever permission defaults apply in print mode.
      local out
      out="$(cd "$cwd" && claude -p --dangerously-skip-permissions --session-id "$session_id" -- "$text" 2>&1 || true)"
      [[ -z "$out" ]] && out="(claude produced no output)"

      reply_text "$out" "$msg_id"
      bump_session_state
    done <<< "$parsed"
  done
}

# ---------- arg parsing ----------

CWD_OVERRIDE=""

while (("$#")); do
  case "$1" in
    --daemon)  install_daemon; exit 0 ;;
    --stop)    stop_daemon; exit 0 ;;
    --cwd)     CWD_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

run_listener
