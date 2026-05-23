#!/usr/bin/env bash
# rotate-queue.sh — track secrets that were exposed (pasted in a chat transcript,
# screenshotted, committed, etc.) and therefore need rotating.
#
# The agent appends here whenever a secret is typed into a chat instead of via
# the safe `add-secret.sh --launch` flow. Keeps a durable, greppable to-rotate list.
#
# Usage:
#   rotate-queue.sh add KEY WHERE [note...]   # WHERE = env | wrangler-secret:<app> | git | screenshot
#   rotate-queue.sh list                      # show open + done, plus CHAT-EXPOSED markers in the env
#   rotate-queue.sh done KEY                   # mark rotated
set -euo pipefail
Q="$HOME/.claude/.secrets-rotate-queue.md"

ensure() {
  [[ -f "$Q" ]] && return
  cat > "$Q" <<'EOF'
# Secrets rotation queue
# Secrets that were EXPOSED (pasted in chat, screenshotted, committed, etc.).
# Rotate each at its provider, update the env / wrangler secret, then mark done.
# Managed by ro:env (skills/env/scripts/rotate-queue.sh). Gitignored — do not commit.
#
# status | KEY | where | exposed-date | note
EOF
  chmod 600 "$Q" 2>/dev/null || true
}

case "${1:-list}" in
  add)
    ensure
    KEY="${2:?KEY required}"; WHERE="${3:?WHERE required}"; shift 3 || true; NOTE="${*:-}"
    printf 'OPEN | %s | %s | %s | %s\n' "$KEY" "$WHERE" "$(date +%Y-%m-%d)" "$NOTE" >> "$Q"
    echo "⚠️  logged $KEY ($WHERE) to the rotation queue: $Q"
    ;;
  done)
    ensure
    KEY="${2:?KEY required}"
    tmp="$(mktemp)"; sed "s/^OPEN | ${KEY} |/DONE | ${KEY} |/" "$Q" > "$tmp" && cat "$tmp" > "$Q" && rm -f "$tmp"
    echo "✅ marked $KEY rotated."
    ;;
  list)
    ensure
    echo "=== rotation queue ($Q) ==="
    grep -E '^(OPEN|DONE) ' "$Q" || echo "(empty)"
    echo
    echo "=== CHAT-EXPOSED / ROTATE markers in the active env ==="
    f="$(ro context env 2>/dev/null || echo "$HOME/.claude/.env")"
    grep -niE 'chat-exposed|rotate' "$f" 2>/dev/null || echo "(none)"
    ;;
  *) echo "usage: rotate-queue.sh {add KEY WHERE [note] | list | done KEY}" >&2; exit 2 ;;
esac
