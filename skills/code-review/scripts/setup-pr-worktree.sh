#!/usr/bin/env bash
# Set up a reusable sibling worktree for reviewing PRs side-by-side with main.
#
# Usage:
#   setup-pr-worktree.sh <PR>                    # current repo, default port 3001
#   setup-pr-worktree.sh <PR> --port 3002        # alt port
#   setup-pr-worktree.sh <PR> --repo /path       # explicit repo path
#   setup-pr-worktree.sh --switch <PR>           # reuse the worktree on a new PR (no fresh install)
#   setup-pr-worktree.sh --status                # show what's checked out
#   setup-pr-worktree.sh --cleanup               # remove the worktree
#
# The worktree is named `<repo>-code-review` (generic, reusable across PRs)
# and lives next to the main checkout. Per-worktree state isolated automatically:
# .wrangler/, node_modules/, .dev.vars, .code-review/.
#
# Designed for TanStack Start + Cloudflare Workers (D1) but degrades gracefully
# on other stacks: missing tools just skip their step.

set -euo pipefail

PORT=3001
REPO_PATH=""
PR=""
MODE="setup"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --repo) REPO_PATH="$2"; shift 2 ;;
    --switch) MODE="switch"; PR="$2"; shift 2 ;;
    --status) MODE="status"; shift ;;
    --cleanup) MODE="cleanup"; shift ;;
    --help|-h)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      if [[ -z "$PR" && "$1" =~ ^[0-9]+$ ]]; then
        PR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

# Resolve repo path
if [[ -z "$REPO_PATH" ]]; then
  REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
if [[ -z "$REPO_PATH" || ! -d "$REPO_PATH/.git" && ! -f "$REPO_PATH/.git" ]]; then
  echo "✗ Not in a git repo and no --repo given" >&2
  exit 1
fi

REPO_NAME=$(basename "$REPO_PATH")
WORKTREE_PATH="$(dirname "$REPO_PATH")/${REPO_NAME}-code-review"

# Tooling detection
detect_pm() {
  if [[ -f "$REPO_PATH/pnpm-lock.yaml" ]]; then echo pnpm
  elif [[ -f "$REPO_PATH/yarn.lock" ]]; then echo yarn
  elif [[ -f "$REPO_PATH/bun.lockb" ]]; then echo bun
  elif [[ -f "$REPO_PATH/package-lock.json" ]]; then echo npm
  else echo npm
  fi
}
PM=$(detect_pm)

detect_d1_db() {
  local cfg="$REPO_PATH/wrangler.jsonc"
  [[ -f "$cfg" ]] || cfg="$REPO_PATH/wrangler.toml"
  [[ -f "$cfg" ]] || return 1
  grep -E '"database_name"|database_name' "$cfg" 2>/dev/null \
    | head -1 \
    | sed -E 's/.*"database_name"[[:space:]]*[:=][[:space:]]*"([^"]+)".*/\1/; s/.*database_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
}

case "$MODE" in
  status)
    git -C "$REPO_PATH" worktree list | grep "$REPO_NAME-code-review" || echo "(no code-review worktree)"
    exit 0
    ;;

  cleanup)
    if git -C "$REPO_PATH" worktree list | grep -q "$REPO_NAME-code-review"; then
      git -C "$REPO_PATH" worktree remove "$WORKTREE_PATH" --force
      echo "✓ Removed $WORKTREE_PATH"
    else
      echo "(nothing to clean up)"
    fi
    exit 0
    ;;

  switch)
    if [[ -z "$PR" ]]; then
      echo "✗ --switch requires a PR number" >&2
      exit 1
    fi
    if [[ ! -d "$WORKTREE_PATH" ]]; then
      echo "✗ No existing worktree at $WORKTREE_PATH — run without --switch first" >&2
      exit 1
    fi
    BRANCH=$(gh -R "$(gh repo view --json nameWithOwner -q .nameWithOwner)" pr view "$PR" --json headRefName -q .headRefName)
    git -C "$WORKTREE_PATH" fetch origin "$BRANCH:$BRANCH" 2>/dev/null || git -C "$WORKTREE_PATH" fetch origin "$BRANCH"
    git -C "$WORKTREE_PATH" checkout "$BRANCH"
    git -C "$WORKTREE_PATH" reset --hard "origin/$BRANCH"
    echo "✓ Worktree now on $BRANCH (PR #$PR)"
    DB=$(detect_d1_db || true)
    if [[ -n "$DB" ]] && command -v pnpm >/dev/null 2>&1; then
      echo "▶ Re-applying D1 migrations in worktree (in case schema differs)"
      (cd "$WORKTREE_PATH" && $PM wrangler d1 migrations apply "$DB" --local) || true
    fi
    echo ""
    echo "Start dev:"
    echo "  cd $WORKTREE_PATH && $PM dev -- --port $PORT"
    exit 0
    ;;

  setup)
    if [[ -z "$PR" ]]; then
      echo "✗ Pass a PR number, or --switch / --status / --cleanup" >&2
      exit 1
    fi

    if git -C "$REPO_PATH" worktree list | grep -q "$REPO_NAME-code-review"; then
      echo "▶ Worktree already exists; switching to PR #$PR"
      exec "$0" --switch "$PR" --repo "$REPO_PATH" --port "$PORT"
    fi

    BRANCH=$(gh -R "$(gh repo view --json nameWithOwner -q .nameWithOwner)" pr view "$PR" --json headRefName -q .headRefName)
    echo "▶ Creating worktree at $WORKTREE_PATH on $BRANCH"
    git -C "$REPO_PATH" fetch origin "$BRANCH" 2>&1 | tail -1
    git -C "$REPO_PATH" worktree add "$WORKTREE_PATH" "$BRANCH"

    if [[ -f "$REPO_PATH/.dev.vars" ]]; then
      cp "$REPO_PATH/.dev.vars" "$WORKTREE_PATH/.dev.vars"
      echo "✓ Copied .dev.vars from main checkout"
    fi
    if [[ -f "$REPO_PATH/.env.local" ]]; then
      cp "$REPO_PATH/.env.local" "$WORKTREE_PATH/.env.local"
      echo "✓ Copied .env.local from main checkout"
    fi

    echo "▶ Installing dependencies with $PM (this takes a minute)"
    (cd "$WORKTREE_PATH" && $PM install) 2>&1 | tail -3

    DB=$(detect_d1_db || true)
    if [[ -n "$DB" ]]; then
      echo "▶ Applying D1 migrations to local SQLite in worktree (isolated from main)"
      (cd "$WORKTREE_PATH" && $PM wrangler d1 migrations apply "$DB" --local) 2>&1 | tail -3
    fi

    cat <<EOF

✓ Worktree ready at $WORKTREE_PATH
  Branch: $BRANCH (PR #$PR)
  Local D1: isolated (.wrangler/state/ is per-cwd)
  Package manager: $PM

Next:
  # Terminal 1 (main)
  cd $REPO_PATH && $PM dev

  # Terminal 2 (PR)
  cd $WORKTREE_PATH && $PM dev -- --port $PORT

If Clerk (or any OAuth) is in the mix:
  Add http://localhost:$PORT to allowed redirect URLs in the provider dashboard
  (one-time setup — both ports then work simultaneously).

Switch to a different PR later (reuse the worktree):
  $0 --switch <other-PR>

Clean up when done:
  $0 --cleanup
EOF
    ;;
esac
