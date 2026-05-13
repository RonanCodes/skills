#!/usr/bin/env bash
# hooks/nudge-check.sh
#
# Runs on every SessionStart (startup). For each registered nudge in
# hooks/nudges/*.sh, decides whether to prompt the user about onboarding
# that feature, and emits a marker line into session context if so.
#
# Markers look like:
#   RO_SKILLS_NUDGE: <name> | <summary> | setup: <hint>
# The handler rule lives in the user's global CLAUDE.md (section
# "RO_SKILLS_NUDGE markers"), which is always loaded. The model reads the
# marker, asks the user via AskUserQuestion (Set up now / Remind later /
# Never), and writes the answer to ~/.claude/.ro/nudge-<name>.
#
# State file format (one of):
#   dismissed              — never ask again
#   remind:YYYY-MM-DD      — silent until that date
#   (file absent)          — eligible to nudge if nudge_check returns non-zero
#
# A nudge file at hooks/nudges/<name>.sh defines:
#   NUDGE_NAME, NUDGE_SUMMARY, NUDGE_SETUP_HINT  (strings)
#   nudge_check()                                (returns 0 if satisfied)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUDGES_DIR="$SCRIPT_DIR/nudges"
STATE_DIR="${RO_SKILLS_STATE_DIR:-$HOME/.claude/.ro}"
ENV_FILE="${RO_SKILLS_ENV_FILE:-$HOME/.claude/.env}"

mkdir -p "$STATE_DIR"

# Load user env so nudge_check funcs can see tokens etc.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

TODAY="$(date +%Y-%m-%d)"
PENDING=()

shopt -s nullglob
for nudge_file in "$NUDGES_DIR"/*.sh; do
  # Reset metadata before sourcing each nudge.
  NUDGE_NAME=""
  NUDGE_SUMMARY=""
  NUDGE_SETUP_HINT=""
  unset -f nudge_check 2>/dev/null || true

  # shellcheck disable=SC1090
  source "$nudge_file" || continue
  [[ -z "$NUDGE_NAME" ]] && continue

  state_file="$STATE_DIR/nudge-$NUDGE_NAME"
  if [[ -f "$state_file" ]]; then
    state="$(head -n1 "$state_file" 2>/dev/null || echo "")"
    case "$state" in
      dismissed) continue ;;
      remind:*)
        when="${state#remind:}"
        [[ "$when" > "$TODAY" || "$when" == "$TODAY" ]] && continue
        ;;
    esac
  fi

  if declare -F nudge_check >/dev/null && nudge_check; then
    continue
  fi

  PENDING+=("RO_SKILLS_NUDGE: $NUDGE_NAME | $NUDGE_SUMMARY | setup: $NUDGE_SETUP_HINT")
done

(( ${#PENDING[@]} == 0 )) && exit 0

for line in "${PENDING[@]}"; do
  echo "$line"
done

# Append the handler instructions so the model knows how to react to the
# markers above. Keeping the handler co-located with the markers means the
# whole onboarding flow is portable: it travels with the plugin to any
# machine, no per-user CLAUDE.md edits required.
HANDLER_FILE="$SCRIPT_DIR/nudge-handler.md"
if [[ -f "$HANDLER_FILE" ]]; then
  echo ""
  cat "$HANDLER_FILE"
fi

exit 0
