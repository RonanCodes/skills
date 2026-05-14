#!/usr/bin/env bash
# telegram/scripts/notify.sh
#
# End-of-run ping with title envelope. Mirrors /ro:pushover's interface so
# the global firing rule can hit both with one call shape.
#
# Renders as:
#   *Title*
#
#   message body
#
# Reads TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID from ~/.claude/.env.

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  notify.sh <message> [--title <title>] [--silent]

Options:
  --title <title>   Bold header above the message. Defaults to "Claude Code".
  --silent          Send with no notification sound (disable_notification).

Examples:
  notify.sh "night shift done - 7 stories merged"
  notify.sh "ralph paused on auth approach" --title "Night shift"
USAGE
  exit 2
}

[[ $# -eq 0 ]] && usage

MESSAGE=""
TITLE="Claude Code"
SILENT_FLAG=""

while (("$#")); do
  case "$1" in
    --title)   TITLE="${2:-}"; shift 2 ;;
    --silent)  SILENT_FLAG="--disable-notification"; shift ;;
    -h|--help) usage ;;
    --*)       echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [[ -z "$MESSAGE" ]]; then MESSAGE="$1"
      else MESSAGE="$MESSAGE $1"
      fi
      shift ;;
  esac
done

[[ -z "$MESSAGE" ]] && { echo "error: message is required" >&2; usage; }

# Escape MarkdownV2 reserved chars. Python beats sed for portable regex on macOS.
# Telegram MarkdownV2 reserved: _ * [ ] ( ) ~ ` > # + - = | { } . !
escape_mdv2() {
  python3 -c '
import sys
s = sys.argv[1]
reserved = r"_*[]()~`>#+-=|{}.!\\"
out = "".join(("\\" + c) if c in reserved else c for c in s)
sys.stdout.write(out)
' "$1"
}

ESC_TITLE="$(escape_mdv2 "$TITLE")"
ESC_BODY="$(escape_mdv2 "$MESSAGE")"

BODY=$'*'"${ESC_TITLE}"$'*\n\n'"${ESC_BODY}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/send.sh" "$BODY" \
  --parse-mode MarkdownV2 \
  ${SILENT_FLAG}
