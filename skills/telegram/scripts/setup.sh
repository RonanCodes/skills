#!/usr/bin/env bash
# telegram/scripts/setup.sh
#
# Walks the user through Telegram bot creation:
#   1. Prompts them to talk to @BotFather and create a bot
#   2. Captures the bot token, writes it to ~/.claude/.env
#   3. Polls /getUpdates while the user sends a message to the bot
#   4. Captures their chat_id, writes it to ~/.claude/.env
#   5. Sends a confirmation message back via the bot
#
# Idempotent. Re-running re-prompts and rewrites the keys.

set -euo pipefail

ENV_FILE="${TELEGRAM_ENV_FILE:-$HOME/.claude/.env}"
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"

upsert_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    # macOS sed needs the empty extension arg
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    if ! grep -q "^# --- telegram ---" "$ENV_FILE" 2>/dev/null; then
      printf '\n# --- telegram ---\n' >> "$ENV_FILE"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

cat <<'INTRO'

Telegram bot setup
==================

Step 1. Create your bot with BotFather.

  - Open Telegram and message @BotFather (https://t.me/BotFather)
  - Send: /newbot
  - Pick a display name (e.g. "Ronan Claude Bot")
  - Pick a unique username ending in "bot" (e.g. ronan_claude_bot)
  - BotFather replies with an HTTP API token that looks like:
    123456789:ABCdefGhIJKlmNoPQRstuVWxyZ-1234567890

INTRO

read -r -p "Paste the bot token: " BOT_TOKEN
BOT_TOKEN="${BOT_TOKEN// /}"

if [[ -z "$BOT_TOKEN" || ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
  echo "error: token does not look right (expected <digits>:<alnum_>)" >&2
  exit 1
fi

# Verify token with getMe
ME="$(curl --silent --show-error --fail \
  "https://api.telegram.org/bot${BOT_TOKEN}/getMe")" \
  || { echo "error: getMe failed; token rejected by Telegram" >&2; exit 1; }

BOT_USERNAME="$(printf '%s' "$ME" | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["username"])')"
echo "Verified bot: @${BOT_USERNAME}"

upsert_env TELEGRAM_BOT_TOKEN "$BOT_TOKEN"

cat <<INTRO2

Step 2. Capture your chat_id.

  - Open https://t.me/${BOT_USERNAME} (or search for @${BOT_USERNAME} in Telegram)
  - Press Start, then send any message (e.g. "hi")
  - This script will poll for that message and capture your chat_id.

INTRO2

echo "Waiting for a message to @${BOT_USERNAME} ..."

CHAT_ID=""
START_TIME=$(date +%s)
TIMEOUT=180  # 3 minutes

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  if (( ELAPSED > TIMEOUT )); then
    echo "error: timed out after ${TIMEOUT}s waiting for a message" >&2
    exit 1
  fi

  UPDATES="$(curl --silent --show-error --fail \
    "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?timeout=10")" \
    || { sleep 2; continue; }

  CHAT_ID="$(printf '%s' "$UPDATES" | python3 -c '
import json, sys
data = json.load(sys.stdin)
results = data.get("result", [])
for u in reversed(results):
    msg = u.get("message") or u.get("edited_message") or {}
    chat = msg.get("chat", {})
    cid = chat.get("id")
    if cid:
        print(cid)
        break
' 2>/dev/null || true)"

  if [[ -n "$CHAT_ID" ]]; then
    break
  fi
  sleep 1
done

echo "Captured chat_id: ${CHAT_ID}"
upsert_env TELEGRAM_CHAT_ID "$CHAT_ID"

# Send a confirmation back
curl --silent --show-error --fail \
  --form-string "chat_id=${CHAT_ID}" \
  --form-string "text=Telegram bot wired up. /ro:telegram send / notify / listen all live now." \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  > /dev/null

cat <<DONE

Setup complete.

  TELEGRAM_BOT_TOKEN  -> ${ENV_FILE}
  TELEGRAM_CHAT_ID    -> ${ENV_FILE}

Next:
  bash skills/telegram/scripts/send.sh "hello from the cli"
  bash skills/telegram/scripts/notify.sh "test ping" --title "Test"
  bash skills/telegram/scripts/listen.sh         # foreground listener
  bash skills/telegram/scripts/listen.sh --daemon  # always-on (mac launchd)

DONE
