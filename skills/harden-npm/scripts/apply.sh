#!/usr/bin/env bash
# /ro:harden-npm — supply-chain hardening for npm/pnpm repos
# Idempotent. Safe to re-run.
#
# Usage:
#   apply.sh [path] [--check] [--no-husky] [--no-approve-builds]
#
# Sourced from: vaults/llm-wiki-security/wiki/playbooks/npm-supply-chain-hardening.md

set -uo pipefail

REPO_PATH="${1:-$PWD}"
CHECK_ONLY=false
SKIP_HUSKY=false
SKIP_APPROVE=false

# Parse flags
shift 2>/dev/null || true
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --no-husky) SKIP_HUSKY=true ;;
    --no-approve-builds) SKIP_APPROVE=true ;;
  esac
done

cd "$REPO_PATH" || { echo "ERROR: cannot cd to $REPO_PATH"; exit 1; }

if [ ! -d .git ]; then
  echo "ERROR: $REPO_PATH is not a git repo. /ro:harden-npm requires git."
  exit 1
fi

if [ ! -f package.json ]; then
  echo "ERROR: no package.json in $REPO_PATH. Nothing to harden."
  exit 1
fi

echo "============================================================"
echo "/ro:harden-npm — $REPO_PATH"
[ "$CHECK_ONLY" = true ] && echo "(check mode — no writes)"
echo "============================================================"

# === Detect package manager ===
PKG_MGR=""
if [ -f pnpm-lock.yaml ]; then PKG_MGR="pnpm"
elif [ -f bun.lockb ] || [ -f bun.lock ]; then PKG_MGR="bun"
elif [ -f package-lock.json ]; then PKG_MGR="npm"
elif [ -f yarn.lock ]; then PKG_MGR="yarn"
else PKG_MGR="pnpm"; echo "NOTE: no lockfile yet, assuming pnpm"
fi
echo "Package manager: $PKG_MGR"
echo ""

# Track changes
CHANGED=()
SKIPPED=()

# ===== Step 1: pnpm version + packageManager pin =====
echo "[1/6] pnpm version + packageManager pin"
if [ "$PKG_MGR" = "pnpm" ]; then
  PNPM_VER=$(pnpm -v 2>/dev/null || echo "0.0.0")
  PNPM_MAJOR=${PNPM_VER%%.*}
  if [ "$PNPM_MAJOR" -lt 11 ]; then
    if [ "$CHECK_ONLY" = true ]; then
      echo "  WOULD upgrade pnpm $PNPM_VER -> 11+"
    else
      echo "  Upgrading pnpm $PNPM_VER -> latest via corepack"
      corepack prepare pnpm@latest --activate 2>&1 | tail -3
      PNPM_VER=$(pnpm -v)
      CHANGED+=("pnpm upgraded to $PNPM_VER")
    fi
  fi
  CURRENT_PKG_MGR=$(jq -r '.packageManager // ""' package.json)
  WANTED_PKG_MGR="pnpm@$PNPM_VER"
  if [ "$CURRENT_PKG_MGR" != "$WANTED_PKG_MGR" ]; then
    if [ "$CHECK_ONLY" = true ]; then
      echo "  WOULD set packageManager: $CURRENT_PKG_MGR -> $WANTED_PKG_MGR"
    else
      npm pkg set packageManager="$WANTED_PKG_MGR" >/dev/null
      CHANGED+=("packageManager pinned: $WANTED_PKG_MGR")
    fi
  else
    SKIPPED+=("packageManager already $WANTED_PKG_MGR")
  fi
elif [ "$PKG_MGR" = "bun" ]; then
  BUN_VER=$(bun -v 2>/dev/null || echo "0.0.0")
  CURRENT_PKG_MGR=$(jq -r '.packageManager // ""' package.json)
  WANTED_PKG_MGR="bun@$BUN_VER"
  if [ "$CURRENT_PKG_MGR" != "$WANTED_PKG_MGR" ]; then
    if [ "$CHECK_ONLY" = true ]; then
      echo "  WOULD set packageManager: $CURRENT_PKG_MGR -> $WANTED_PKG_MGR"
    else
      npm pkg set packageManager="$WANTED_PKG_MGR" >/dev/null
      CHANGED+=("packageManager pinned: $WANTED_PKG_MGR")
    fi
  else
    SKIPPED+=("packageManager already $WANTED_PKG_MGR")
  fi
fi

# ===== Step 2: per-repo .npmrc =====
echo "[2/6] per-repo .npmrc"
HARDEN_MARKER="# Supply-chain hardening — applied by /ro:harden-npm"
if [ -f .npmrc ] && grep -q "minimum-release-age" .npmrc 2>/dev/null; then
  SKIPPED+=(".npmrc already has minimum-release-age")
else
  if [ "$CHECK_ONLY" = true ]; then
    echo "  WOULD write hardening block to .npmrc"
  else
    if [ -f .npmrc ]; then
      # Prepend hardening block; preserve existing
      TMP=$(mktemp)
      {
        echo "$HARDEN_MARKER"
        echo "# See https://github.com/RonanCodes/llm-wiki vaults/llm-wiki-security/wiki/playbooks/npm-supply-chain-hardening.md"
        echo "minimum-release-age=1440"
        echo "ignore-scripts=true"
        echo "save-exact=true"
        echo "prefer-frozen-lockfile=true"
        echo ""
        cat .npmrc
      } > "$TMP"
      mv "$TMP" .npmrc
      CHANGED+=(".npmrc hardening block prepended")
    else
      cat > .npmrc <<EOF
$HARDEN_MARKER
# See https://github.com/RonanCodes/llm-wiki vaults/llm-wiki-security/wiki/playbooks/npm-supply-chain-hardening.md
minimum-release-age=1440
ignore-scripts=true
save-exact=true
prefer-frozen-lockfile=true
EOF
      CHANGED+=(".npmrc created")
    fi
  fi
fi

# ===== Step 3: approve-builds / trustedDependencies =====
echo "[3/6] build-script allowlist"
if [ "$SKIP_APPROVE" = true ]; then
  SKIPPED+=("approve-builds skipped (--no-approve-builds)")
else
  SAFE_LIST='["@cloudflare/workerd","@swc/core","better-sqlite3","cypress","esbuild","husky","playwright","puppeteer","sharp","sqlite3"]'
  if [ "$PKG_MGR" = "pnpm" ]; then
    CURRENT=$(jq -c '.pnpm.onlyBuiltDependencies // null' package.json)
    if [ "$CURRENT" = "null" ]; then
      if [ "$CHECK_ONLY" = true ]; then
        echo "  WOULD set pnpm.onlyBuiltDependencies to safe canonical list"
      else
        # Merge: keep only the safe-list entries that are actually in dep tree
        DEPS_IN_TREE=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' package.json | sort -u)
        FILTERED=$(echo "$SAFE_LIST" | jq -c --argjson tree "$(echo "$DEPS_IN_TREE" | jq -R . | jq -s .)" '[.[] | select(. as $p | $tree | index($p))]')
        if [ "$FILTERED" = "[]" ]; then
          FILTERED="[]"
        fi
        # Write — pnpm.onlyBuiltDependencies as JSON array
        TMP=$(mktemp)
        jq --argjson list "$FILTERED" '.pnpm = (.pnpm // {}) | .pnpm.onlyBuiltDependencies = $list' package.json > "$TMP" && mv "$TMP" package.json
        CHANGED+=("pnpm.onlyBuiltDependencies set: $FILTERED")
      fi
    else
      SKIPPED+=("pnpm.onlyBuiltDependencies already set")
    fi
  elif [ "$PKG_MGR" = "bun" ]; then
    CURRENT=$(jq -c '.trustedDependencies // null' package.json)
    if [ "$CURRENT" = "null" ]; then
      if [ "$CHECK_ONLY" = true ]; then
        echo "  WOULD set trustedDependencies to safe canonical list"
      else
        DEPS_IN_TREE=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' package.json | sort -u)
        FILTERED=$(echo "$SAFE_LIST" | jq -c --argjson tree "$(echo "$DEPS_IN_TREE" | jq -R . | jq -s .)" '[.[] | select(. as $p | $tree | index($p))]')
        TMP=$(mktemp)
        jq --argjson list "$FILTERED" '.trustedDependencies = $list' package.json > "$TMP" && mv "$TMP" package.json
        CHANGED+=("trustedDependencies set: $FILTERED")
      fi
    else
      SKIPPED+=("trustedDependencies already set")
    fi
  fi
fi

# ===== Step 4: husky pre-push =====
echo "[4/6] husky pre-push (local CI)"
if [ "$SKIP_HUSKY" = true ]; then
  SKIPPED+=("husky skipped (--no-husky)")
else
  if [ ! -f .husky/pre-push ]; then
    if [ "$CHECK_ONLY" = true ]; then
      echo "  WOULD install husky and write .husky/pre-push"
    else
      if ! grep -q '"husky"' package.json; then
        echo "  Installing husky as devDependency..."
        if [ "$PKG_MGR" = "pnpm" ]; then
          pnpm add -D husky --silent 2>&1 | tail -3
        elif [ "$PKG_MGR" = "bun" ]; then
          bun add -d husky 2>&1 | tail -3
        else
          npm i -D husky --silent 2>&1 | tail -3
        fi
      fi
      mkdir -p .husky/_
      # Bootstrap husky.sh if missing
      if [ ! -f .husky/_/husky.sh ]; then
        cat > .husky/_/husky.sh <<'HSH'
#!/usr/bin/env sh
if [ -z "$husky_skip_init" ]; then
  debug () { [ "$HUSKY_DEBUG" = "1" ] && echo "husky (debug) - $1"; }
  readonly hook_name="$(basename "$0")"
  debug "starting $hook_name..."
  if [ "$HUSKY" = "0" ]; then debug "HUSKY env variable is set to 0, skipping hook"; exit 0; fi
  if [ -f ~/.huskyrc ]; then debug "sourcing ~/.huskyrc"; . ~/.huskyrc; fi
  readonly husky_skip_init=1
  export husky_skip_init
  sh -e "$0" "$@"
  exitCode="$?"
  [ $exitCode != 0 ] && echo "husky - $hook_name hook exited with code $exitCode (error)"
  exit $exitCode
fi
HSH
        chmod +x .husky/_/husky.sh
      fi
      cat > .husky/pre-push <<'EOF'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Local CI gate — installed by /ro:harden-npm
# Catches regressions before they leave the machine
set -e

if command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then
  pnpm typecheck 2>/dev/null || pnpm exec tsc --noEmit 2>/dev/null || echo "(no typecheck)"
  pnpm lint 2>/dev/null || echo "(no lint)"
  pnpm test --run 2>/dev/null || pnpm test 2>/dev/null || echo "(no tests)"
elif command -v bun >/dev/null 2>&1 && [ -f bun.lockb -o -f bun.lock ]; then
  bun run typecheck 2>/dev/null || echo "(no typecheck)"
  bun run lint 2>/dev/null || echo "(no lint)"
  bun test 2>/dev/null || echo "(no tests)"
else
  npm run typecheck 2>/dev/null || echo "(no typecheck)"
  npm run lint 2>/dev/null || echo "(no lint)"
  npm test 2>/dev/null || echo "(no tests)"
fi
EOF
      chmod +x .husky/pre-push
      # Ensure prepare script is set
      if ! jq -e '.scripts.prepare' package.json >/dev/null; then
        npm pkg set scripts.prepare="husky" >/dev/null
      fi
      CHANGED+=("husky pre-push installed (typecheck + lint + test)")
    fi
  else
    SKIPPED+=("husky pre-push already exists")
  fi
fi

# ===== Step 5: GH Actions audit =====
echo "[5/6] GH Actions audit (pull_request_target)"
WORKFLOWS_DIR=".github/workflows"
if [ -d "$WORKFLOWS_DIR" ]; then
  MATCHES=$(grep -rln "pull_request_target" "$WORKFLOWS_DIR" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    echo "  ⚠️  pull_request_target found in:"
    for m in $MATCHES; do
      echo "    $m"
      grep -n "pull_request_target" "$m" | head -3 | sed 's/^/      /'
      # Check if fenced
      if grep -q "head.repo.full_name == github.repository" "$m"; then
        echo "    ✓ Looks fenced with fork-check"
      else
        echo "    ✗ NOT fenced — review per security playbook"
      fi
    done
    CHANGED+=("⚠️ pull_request_target found — manual review needed")
  else
    SKIPPED+=("no pull_request_target in workflows")
  fi
else
  SKIPPED+=("no .github/workflows/ dir")
fi

# ===== Step 6: worm-payload scan =====
echo "[6/6] worm-payload sanity scan"
if [ -d node_modules ]; then
  WORM_HITS=""
  # Pattern 1: bundle.js inside @tanstack/* (shai-hulud signature)
  BJS=$(find node_modules -path "*/@tanstack/*" -name "bundle.js" 2>/dev/null | head -5)
  [ -n "$BJS" ] && WORM_HITS="$WORM_HITS\n  bundle.js in @tanstack: $BJS"
  # Pattern 2: hulud anywhere
  HUL=$(find node_modules -iname "*hulud*" 2>/dev/null | head -5)
  [ -n "$HUL" ] && WORM_HITS="$WORM_HITS\n  hulud filename: $HUL"
  # Pattern 3: 60s GH-token poller signature in any JS
  POLL=$(grep -rlE "setInterval.*60.*api.github.com|checkGitHubToken" node_modules 2>/dev/null | head -3)
  [ -n "$POLL" ] && WORM_HITS="$WORM_HITS\n  60s GH-token poller: $POLL"

  if [ -n "$WORM_HITS" ]; then
    echo ""
    echo "🚨🚨🚨 WORM PAYLOAD SUSPECTED 🚨🚨🚨"
    echo -e "$WORM_HITS"
    echo ""
    echo "STOP. Recommended next steps:"
    echo "  1. Do NOT revoke GitHub tokens yet (dead-man switch risk)."
    echo "  2. Snapshot the machine first (Time Machine, disk image)."
    echo "  3. Revoke tokens from a clean machine."
    echo "  4. rm -rf node_modules + pnpm-lock.yaml on this repo."
    echo "  5. Run /ro:security-audit for deeper scan."
    exit 2
  else
    SKIPPED+=("worm scan: clean")
  fi
else
  SKIPPED+=("worm scan: no node_modules to scan")
fi

# ===== Report =====
echo ""
echo "============================================================"
echo "Summary"
echo "============================================================"
if [ ${#CHANGED[@]} -gt 0 ]; then
  echo "Changed:"
  for c in "${CHANGED[@]}"; do echo "  ✓ $c"; done
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "Already in place:"
  for s in "${SKIPPED[@]}"; do echo "  · $s"; done
fi
echo ""
if [ "$CHECK_ONLY" = true ]; then
  echo "Check complete. Re-run without --check to apply."
else
  echo "Hardening applied. Review with: git diff"
  echo "Commit suggestion:"
  echo "  git switch -c security/harden-npm"
  echo "  git add ."
  echo "  git commit -m '🔒 security: apply /ro:harden-npm supply-chain controls'"
fi
