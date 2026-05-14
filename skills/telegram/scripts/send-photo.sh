#!/usr/bin/env bash
# telegram/scripts/send-photo.sh
#
# Send a photo to TELEGRAM_CHAT_ID via the Telegram Bot API.
# Accepts a local file path OR an https URL.
#
# Reads from ~/.claude/.env:
#   TELEGRAM_BOT_TOKEN  (required)
#   TELEGRAM_CHAT_ID    (required)
#
# Telegram API: https://core.telegram.org/bots/api#sendphoto

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  send-photo.sh <path-or-url> [--caption <text>] [--chat-id <id>]
                              [--parse-mode <Markdown|MarkdownV2|HTML>]
                              [--disable-notification]

Examples:
  send-photo.sh ~/Pictures/foo.jpg
  send-photo.sh ~/Pictures/foo.jpg --caption "screenshot"
  send-photo.sh https://example.com/img.png --caption "*bold*" --parse-mode Markdown
USAGE
  exit 2
}

[[ $# -eq 0 ]] && usage

SOURCE=""
CAPTION=""
CHAT_ID_OVERRIDE=""
PARSE_MODE=""
SILENT=""
AS_FILE=""

while (("$#")); do
  case "$1" in
    --caption)              CAPTION="${2:-}"; shift 2 ;;
    --chat-id)              CHAT_ID_OVERRIDE="${2:-}"; shift 2 ;;
    --parse-mode)           PARSE_MODE="${2:-}"; shift 2 ;;
    --disable-notification) SILENT="true"; shift ;;
    --as-file)              AS_FILE="true"; shift ;;
    -h|--help)              usage ;;
    --*)                    echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$SOURCE" ]]; then SOURCE="$1"
      else echo "error: unexpected arg: $1" >&2; usage
      fi
      shift ;;
  esac
done

[[ -z "$SOURCE" ]] && { echo "error: photo path or url is required" >&2; usage; }

ENV_FILE="${TELEGRAM_ENV_FILE:-$HOME/.claude/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set in $ENV_FILE (run /ro:telegram setup)}"
CHAT_ID="${CHAT_ID_OVERRIDE:-${TELEGRAM_CHAT_ID:-}}"
: "${CHAT_ID:?TELEGRAM_CHAT_ID not set in $ENV_FILE (run /ro:telegram setup)}"

# Expand ~ for local paths
if [[ ! "$SOURCE" =~ ^https?:// ]]; then
  SOURCE="${SOURCE/#\~/$HOME}"
  [[ -f "$SOURCE" ]] || { echo "error: file not found: $SOURCE" >&2; exit 1; }
fi

send_request() {
  local endpoint="$1"  # sendPhoto or sendDocument
  local field="$2"     # photo or document
  local args=(
    --silent --show-error
    --form-string "chat_id=${CHAT_ID}"
  )
  if [[ "$SOURCE" =~ ^https?:// ]]; then
    args+=(--form-string "${field}=${SOURCE}")
  else
    args+=(--form "${field}=@${SOURCE}")
  fi
  [[ -n "$CAPTION"    ]] && args+=(--form-string "caption=${CAPTION}")
  [[ -n "$PARSE_MODE" ]] && args+=(--form-string "parse_mode=${PARSE_MODE}")
  [[ -n "$SILENT"     ]] && args+=(--form-string "disable_notification=true")
  curl "${args[@]}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${endpoint}"
}

if [[ -n "$AS_FILE" ]]; then
  RESPONSE=$(send_request "sendDocument" "document")
else
  RESPONSE=$(send_request "sendPhoto" "photo")
  # Auto-fallback: if Telegram rejects on dimensions or size, retry as document.
  if echo "$RESPONSE" | grep -qE 'PHOTO_INVALID_DIMENSIONS|file is too big|PHOTO_SAVE_FILE_INVALID'; then
    echo "sendPhoto rejected (dimensions/size), retrying as sendDocument..." >&2
    RESPONSE=$(send_request "sendDocument" "document")
  fi
fi

echo "$RESPONSE"
echo "$RESPONSE" | grep -q '"ok":true' || exit 1
