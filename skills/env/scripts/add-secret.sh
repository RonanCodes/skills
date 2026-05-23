#!/usr/bin/env bash
# add-secret.sh — add/update ONE secret in the active ~/.claude/.env file
# WITHOUT the value ever passing through an agent's stdin/stdout.
#
# The agent calls this with --launch; it opens a NEW Terminal window where
# the human types the secret (read -rs, hidden). The value is written to the
# env file non-destructively (in-place update if the key exists, else appended
# under an owner-tagged block), after a timestamped backup. The agent never
# sees the value.
#
# Usage:
#   bash add-secret.sh --launch KEY [OWNER] [comment...]      # agent: opens Terminal
#   bash add-secret.sh --interactive KEY [OWNER] [comment...] # runs the prompts here
#   bash add-secret.sh KEY [OWNER] [comment...]               # alias for --interactive
#
# OWNER ∈ {SIMPLICITY, DATAFORCE, PERSONAL} (free text accepted; used as a tag).
set -euo pipefail

MODE="interactive"
case "${1:-}" in
  --launch) MODE="launch"; shift ;;
  --interactive) MODE="interactive"; shift ;;
esac

KEY="${1:-}"; OWNER="${2:-}"; shift || true; shift || true
COMMENT="${*:-}"

if [[ -z "$KEY" ]]; then
  echo "usage: add-secret.sh [--launch|--interactive] KEY [OWNER] [comment]" >&2; exit 2
fi
if [[ ! "$KEY" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
  echo "✘ KEY must be UPPER_SNAKE_CASE (got: $KEY)" >&2; exit 2
fi

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Resolve the active env file (cwd-aware via `ro context env`, else default).
resolve_envfile() {
  local f
  f="$(ro context env 2>/dev/null || true)"
  [[ -z "$f" ]] && f="$HOME/.claude/.env"
  # follow symlink to the real file so backups/writes hit the target, not the link
  if [[ -L "$f" ]]; then f="$(readlink -f "$f")"; fi
  printf '%s' "$f"
}

if [[ "$MODE" == "launch" ]]; then
  # Open a Terminal window running the interactive flow. The human types the
  # secret there; this process returns immediately. macOS (osascript).
  if command -v osascript >/dev/null 2>&1; then
    osascript >/dev/null 2>&1 <<OSA
tell application "Terminal"
  activate
  do script "bash '$SELF' --interactive '$KEY' '$OWNER' '$COMMENT'; echo; echo '(window stays open — close it when done)'"
end tell
OSA
    echo "✅ Opened a Terminal window. Type the secret for \$$KEY there — it never touches this session."
    exit 0
  fi
  echo "✘ osascript not available; run interactively yourself:" >&2
  echo "    bash '$SELF' --interactive '$KEY' '$OWNER' '$COMMENT'" >&2
  exit 1
fi

# ---- interactive flow (runs in a real TTY) ----
ENVFILE="$(resolve_envfile)"
[[ -f "$ENVFILE" ]] || { echo "✘ env file not found: $ENVFILE" >&2; exit 1; }

echo "Env file : $ENVFILE"
echo "Key      : $KEY"
echo "Owner    : ${OWNER:-(none)}"
echo "Comment  : ${COMMENT:-(none)}"
echo
printf 'Paste the secret value for %s (hidden), then Enter: ' "$KEY"
IFS= read -rs VALUE; echo
if [[ -z "$VALUE" ]]; then echo "✘ empty value — aborted, nothing changed." >&2; exit 1; fi

# Backup (timestamped, 600), keep things recoverable + non-destructive.
BACKUP="$ENVFILE.bak.$(date +%Y%m%d-%H%M%S)"
cp "$ENVFILE" "$BACKUP"; chmod 600 "$BACKUP" 2>/dev/null || true

before_lines=$(wc -l < "$ENVFILE")
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT

if grep -qE "^${KEY}=" "$ENVFILE"; then
  # Update in place — value passed via env (NEWVAL), never via argv (ps-safe).
  NEWVAL="$VALUE" awk -v key="$KEY" '
    $0 ~ "^"key"=" { print key"="ENVIRON["NEWVAL"]; next }
    { print }
  ' "$ENVFILE" > "$tmp"
  ACTION="updated in place"
else
  # Append a tagged block at the end (non-destructive).
  cp "$ENVFILE" "$tmp"
  {
    printf '\n'
    [[ -n "$OWNER" || -n "$COMMENT" ]] && printf '# [%s] %s (added %s via ro:env)\n' "${OWNER:-UNTAGGED}" "$COMMENT" "$(date +%Y-%m-%d)"
    NEWVAL="$VALUE" awk -v key="$KEY" 'BEGIN{print key"="ENVIRON["NEWVAL"]}'
  } >> "$tmp"
  ACTION="appended (owner: ${OWNER:-UNTAGGED})"
fi

# Write back via cat > so a symlinked path is preserved (here ENVFILE is already real).
cat "$tmp" > "$ENVFILE"
unset VALUE NEWVAL

after_lines=$(wc -l < "$ENVFILE")
if ! grep -qE "^${KEY}=" "$ENVFILE"; then
  echo "✘ write verification failed — restoring backup."; cp "$BACKUP" "$ENVFILE"; exit 1
fi
echo "✅ $KEY $ACTION."
echo "   file: $ENVFILE  (lines $before_lines → $after_lines)"
echo "   backup: $BACKUP"
echo "   re-source with: set -a && source ~/.claude/.env && set +a"
