#!/usr/bin/env bash
# Migrates a target repo to the canonical label system defined in canon/labels.yml.
#
# Usage:
#   scripts/migrate-labels.sh [--dry-run] <owner/repo>
#
# Behaviour:
#   1. Creates every canonical label that doesn't yet exist on the repo.
#   2. Updates colour/description on labels that exist but drift from canon.
#   3. Renames legacy labels via the rename_map (preserves issue linkage).
#   4. Backfills kind:* + lifecycle on open issues that don't have them.
#
# Idempotent: re-running is a no-op for repos already on the canon.
# Verbose: prints what it's doing. Use --dry-run to preview without writing.
#
# Requires: gh (authenticated), python3 with PyYAML.

set -euo pipefail

DRY_RUN=0
REPO=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$REPO" ]]; then
        REPO="$arg"
      else
        echo "unexpected argument: $arg" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "usage: $0 [--dry-run] <owner/repo>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANON_DIR="$SCRIPT_DIR/../canon"
LABELS_YML="$CANON_DIR/labels.yml"

# Temp dir for the python helper scripts. We can't use heredocs inside $() pipes
# because bash routes the heredoc to the last process in the pipeline.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/parse_yaml.py" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for section in ("lifecycle", "kind", "modifiers"):
    for entry in data.get(section, []):
        name = entry["name"]
        color = entry["color"]
        desc = entry.get("description", "").replace("\t", " ")
        print(f"label\t{name}\t{color}\t{desc}")
for old, new in (data.get("rename_map") or {}).items():
    print(f"rename\t{old}\t{new}\t")
PY

cat > "$TMP_DIR/parse_existing.py" <<'PY'
import json, sys
data = json.load(sys.stdin)
for l in data:
    name = l.get("name", "")
    color = (l.get("color") or "").upper()
    desc = (l.get("description") or "").replace("\t", " ")
    print(f"{name}\t{color}\t{desc}")
PY

cat > "$TMP_DIR/backfill_issues.py" <<'PY'
import json, sys, subprocess
repo = sys.argv[1]
dry  = sys.argv[2] == "1"
path = sys.argv[3]
with open(path) as f:
    issues = json.load(f) or []

KIND_LABELS = {"kind:prd", "kind:slice", "kind:incident", "kind:chore"}
LIFECYCLE_LABELS = {"needs-grilling", "ready-for-agent", "in-progress", "needs-human"}

def has_any(labels, group):
    return any(l["name"] in group for l in labels)

def classify_kind(title, body):
    body = body or ""
    if body.lstrip().startswith("## Parent"):
        return "kind:slice"
    if "## Problem Statement" in body or "## Goals" in body or "## Success Criteria" in body:
        return "kind:prd"
    return "kind:chore"

for issue in issues:
    n = issue["number"]
    title = issue.get("title", "")
    body = issue.get("body") or ""
    labels = issue.get("labels", [])
    to_add = []
    if not has_any(labels, KIND_LABELS):
        to_add.append(classify_kind(title, body))
    if not has_any(labels, LIFECYCLE_LABELS):
        to_add.append("ready-for-agent")
    if not to_add:
        print(f"  ok     #{n} {title[:60]}")
        continue
    print(f"  label  #{n} += {to_add}   {title[:60]}")
    if not dry:
        cmd = ["gh", "issue", "edit", str(n), "--repo", repo]
        for lab in to_add:
            cmd += ["--add-label", lab]
        subprocess.run(cmd, check=False)
PY

if [[ ! -f "$LABELS_YML" ]]; then
  echo "labels.yml not found at $LABELS_YML" >&2
  exit 1
fi

# Confirm repo exists. If not, log and bail with a soft exit (caller can continue).
if ! gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1; then
  echo "[skip] $REPO not reachable (private+no-access, or doesn't exist)"
  exit 0
fi

echo "==> Migrating labels on $REPO (dry-run=$DRY_RUN)"

# Render labels.yml into a tab-separated list: kind<TAB>name<TAB>color<TAB>description
# kind ∈ {label, rename}
PARSED=$(python3 "$TMP_DIR/parse_yaml.py" "$LABELS_YML")

# Pull existing labels once.
EXISTING=$(gh label list --repo "$REPO" --limit 200 --json name,color,description | python3 "$TMP_DIR/parse_existing.py")

label_exists() {
  local name="$1"
  echo "$EXISTING" | awk -F'\t' -v n="$name" '$1==n {found=1} END {exit !found}'
}

label_drift() {
  # Returns 0 if existing label colour or description differs from canon.
  local name="$1" want_color="$2" want_desc="$3"
  local row
  row=$(echo "$EXISTING" | awk -F'\t' -v n="$name" '$1==n {print; exit}')
  [[ -z "$row" ]] && return 1
  local cur_color cur_desc
  cur_color=$(echo "$row" | awk -F'\t' '{print $2}')
  cur_desc=$(echo "$row" | awk -F'\t' '{print $3}')
  [[ "$cur_color" != "$(echo "$want_color" | tr '[:lower:]' '[:upper:]')" ]] && return 0
  [[ "$cur_desc" != "$want_desc" ]] && return 0
  return 1
}

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# Step 1: rename legacy labels FIRST, so we preserve issue linkage instead of
# creating new+orphaning old. After this phase, EXISTING is stale; we re-snapshot.
echo "--> Phase 1: rename legacy labels"
while IFS=$'\t' read -r kind old new _; do
  [[ "$kind" == "rename" ]] || continue
  if label_exists "$old"; then
    if label_exists "$new"; then
      # Both exist (half-migrated). Move issues from old to new, then delete old.
      echo "  conflict $old -> $new (both exist); migrating issues"
      issues=$(gh issue list --repo "$REPO" --label "$old" --state all --limit 200 --json number -q '.[].number' || true)
      for n in $issues; do
        run gh issue edit "$n" --repo "$REPO" --add-label "$new" --remove-label "$old"
      done
      run gh label delete "$old" --repo "$REPO" --yes
    else
      echo "  rename $old -> $new"
      run gh label edit "$old" --repo "$REPO" --name "$new"
    fi
  fi
done <<<"$PARSED"

# Re-snapshot labels after renames so Phase 2 sees the up-to-date state.
EXISTING=$(gh label list --repo "$REPO" --limit 200 --json name,color,description | python3 "$TMP_DIR/parse_existing.py")

# Step 2: create missing canonical labels, fix drift on existing ones.
echo "--> Phase 2: ensure canonical labels exist"
while IFS=$'\t' read -r kind name color desc; do
  [[ "$kind" == "label" ]] || continue
  if label_exists "$name"; then
    if label_drift "$name" "$color" "$desc"; then
      echo "  update $name (colour/description drift)"
      run gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc"
    else
      echo "  ok     $name"
    fi
  else
    echo "  create $name"
    run gh label create "$name" --repo "$REPO" --color "$color" --description "$desc"
  fi
done <<<"$PARSED"

# Step 4: backfill kind:* + lifecycle on open issues that lack them.
echo "--> Phase 3: backfill kind:* + lifecycle on open issues"
OPEN_ISSUES_FILE="$TMP_DIR/open_issues.json"
gh issue list --repo "$REPO" --state open --limit 300 --json number,title,body,labels > "$OPEN_ISSUES_FILE"
python3 "$TMP_DIR/backfill_issues.py" "$REPO" "$DRY_RUN" "$OPEN_ISSUES_FILE"

echo "==> Done with $REPO"
