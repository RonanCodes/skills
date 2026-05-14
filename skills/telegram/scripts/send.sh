#!/usr/bin/env bash
# telegram/scripts/send.sh
#
# Send a message to TELEGRAM_CHAT_ID via the Telegram Bot API.
# One curl, one message. No envelope, no markdown by default.
#
# Reads from ~/.claude/.env:
#   TELEGRAM_BOT_TOKEN  (required)
#   TELEGRAM_CHAT_ID    (required)
#
# Telegram API: https://core.telegram.org/bots/api#sendmessage

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  send.sh <message> [--chat-id <id>] [--parse-mode <Markdown|MarkdownV2|HTML>]
                    [--reply-to <message_id>] [--disable-notification]

Options:
  --chat-id <id>           Override TELEGRAM_CHAT_ID for this call.
  --parse-mode <mode>      Markdown / MarkdownV2 / HTML. Default plain text.
  --reply-to <message_id>  Reply to a specific message.
  --disable-notification   Send silently (no sound, no banner).

Examples:
  send.sh "hello"
  send.sh "*bold*" --parse-mode Markdown
USAGE
  exit 2
}

[[ $# -eq 0 ]] && usage

MESSAGE=""
CHAT_ID_OVERRIDE=""
PARSE_MODE=""
REPLY_TO=""
SILENT=""

while (("$#")); do
  case "$1" in
    --chat-id)              CHAT_ID_OVERRIDE="${2:-}"; shift 2 ;;
    --parse-mode)           PARSE_MODE="${2:-}"; shift 2 ;;
    --reply-to)             REPLY_TO="${2:-}"; shift 2 ;;
    --disable-notification) SILENT="true"; shift ;;
    -h|--help)              usage ;;
    --*)                    echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$MESSAGE" ]]; then MESSAGE="$1"
      else MESSAGE="$MESSAGE $1"
      fi
      shift ;;
  esac
done

[[ -z "$MESSAGE" ]] && { echo "error: message is required" >&2; usage; }

ENV_FILE="${TELEGRAM_ENV_FILE:-$HOME/.claude/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set in $ENV_FILE (run /ro:telegram setup)}"
CHAT_ID="${CHAT_ID_OVERRIDE:-${TELEGRAM_CHAT_ID:-}}"
: "${CHAT_ID:?TELEGRAM_CHAT_ID not set in $ENV_FILE (run /ro:telegram setup)}"

# Telegram caps sendMessage at 4096 chars. Split if needed.
MAX_LEN=4000

send_one() {
  local text="$1"
  local args=(
    --silent --show-error --fail
    --form-string "chat_id=${CHAT_ID}"
    --form-string "text=${text}"
  )
  [[ -n "$PARSE_MODE" ]] && args+=(--form-string "parse_mode=${PARSE_MODE}")
  [[ -n "$REPLY_TO"   ]] && args+=(--form-string "reply_to_message_id=${REPLY_TO}")
  [[ -n "$SILENT"     ]] && args+=(--form-string "disable_notification=true")

  curl "${args[@]}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
  echo
}

LEN=${#MESSAGE}
if (( LEN <= MAX_LEN )); then
  send_one "$MESSAGE"
else
  # Split into chunks, suffix (part N/M)
  TOTAL=$(( (LEN + MAX_LEN - 1) / MAX_LEN ))
  IDX=1
  POS=0
  while (( POS < LEN )); do
    CHUNK="${MESSAGE:$POS:$MAX_LEN}"
    SUFFIX=$'\n\n(part '"${IDX}/${TOTAL}"')'
    send_one "${CHUNK}${SUFFIX}"
    POS=$(( POS + MAX_LEN ))
    IDX=$(( IDX + 1 ))
    sleep 0.3  # avoid hitting flood limits
  done
fi
