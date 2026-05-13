#!/usr/bin/env bash
# pushover/scripts/notify.sh
#
# Fire a Pushover notification. Wraps POST https://api.pushover.net/1/messages.json.
#
# Reads from ~/.claude/.env:
#   PUSHOVER_APP_TOKEN  (required — the application API token, ~30 chars)
#   PUSHOVER_USER_KEY   (required — the user/group key, ~30 chars)
#
# Pushover API reference: https://pushover.net/api

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  notify.sh <message> [--title <title>] [--priority <-2..2>] [--sound <name>]
                      [--url <url>] [--url-title <text>] [--device <name>]

Options:
  --title <title>      Bold header above the message. Defaults to "Claude Code".
  --priority <n>       -2 silent, -1 quiet, 0 normal (default), 1 high (bypass quiet hours),
                       2 emergency (requires retry+expire, not exposed here — use 1 instead).
  --sound <name>       Override notification sound. e.g. magic, cosmic, pushover, none.
                       Full list: https://pushover.net/api#sounds
  --url <url>          Supplementary URL attached to the notification.
  --url-title <text>   Display text for --url.
  --device <name>      Send to a specific registered device only.

Examples:
  notify.sh "night shift done — ready for review"
  notify.sh "ralph loop finished" --title "Night shift" --sound magic
  notify.sh "PR #42 ready" --url "https://github.com/me/repo/pull/42" --url-title "Open PR"
USAGE
  exit 2
}

[[ $# -eq 0 ]] && usage

MESSAGE=""
TITLE="Claude Code"
PRIORITY=""
SOUND=""
URL=""
URL_TITLE=""
DEVICE=""

while (("$#")); do
  case "$1" in
    --title)     TITLE="${2:-}"; shift 2 ;;
    --priority)  PRIORITY="${2:-}"; shift 2 ;;
    --sound)     SOUND="${2:-}"; shift 2 ;;
    --url)       URL="${2:-}"; shift 2 ;;
    --url-title) URL_TITLE="${2:-}"; shift 2 ;;
    --device)    DEVICE="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    --*)         echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$MESSAGE" ]]; then MESSAGE="$1"
      else MESSAGE="$MESSAGE $1"
      fi
      shift ;;
  esac
done

[[ -z "$MESSAGE" ]] && { echo "error: message is required" >&2; usage; }

ENV_FILE="${PUSHOVER_ENV_FILE:-$HOME/.claude/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${PUSHOVER_APP_TOKEN:?PUSHOVER_APP_TOKEN not set in $ENV_FILE}"
: "${PUSHOVER_USER_KEY:?PUSHOVER_USER_KEY not set in $ENV_FILE}"

ARGS=(
  --silent --show-error --fail
  --form-string "token=$PUSHOVER_APP_TOKEN"
  --form-string "user=$PUSHOVER_USER_KEY"
  --form-string "message=$MESSAGE"
  --form-string "title=$TITLE"
)
[[ -n "$PRIORITY"  ]] && ARGS+=(--form-string "priority=$PRIORITY")
[[ -n "$SOUND"     ]] && ARGS+=(--form-string "sound=$SOUND")
[[ -n "$URL"       ]] && ARGS+=(--form-string "url=$URL")
[[ -n "$URL_TITLE" ]] && ARGS+=(--form-string "url_title=$URL_TITLE")
[[ -n "$DEVICE"    ]] && ARGS+=(--form-string "device=$DEVICE")

RESPONSE="$(curl "${ARGS[@]}" https://api.pushover.net/1/messages.json)"
echo "$RESPONSE"

# Pushover returns {"status":1,...} on success, {"status":0,"errors":[...]} on failure.
STATUS="$(echo "$RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",0))' 2>/dev/null || echo 0)"
[[ "$STATUS" == "1" ]] || exit 1
