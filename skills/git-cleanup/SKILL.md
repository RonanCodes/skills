---
name: git-cleanup
description: Prune local git branches that are already on main, detecting classic merges, squash-merges via merged PRs, and content-in-main via diff. Confirms with the user before deleting. Use when the user wants to clean up, prune, or delete merged branches, or asks which branches are safe to delete.
category: development
argument-hint: [--base main] [--dry-run] [--include-archive] [--yes]
allowed-tools: Bash(git *) Bash(gh *)
---

# Git Cleanup

List every local branch, classify it against `main`, and delete the ones the user confirms. Works with squash-merge workflows where `git branch --merged` is blind.

## Why this exists

`git branch --merged main` only detects merge-commits and fast-forwards. Under a squash-only workflow (see `/ro:new-tanstack-app` step 13a and `connections-helper/docs/adr/0002-github-branch-protection-squash-only-merges.md`), branches get merged by replaying their diff into a new single commit on `main`. The original commit SHAs are never in `main`'s history, so `--merged` marks them as unmerged even though their content is fully landed.

This skill combines three detection strategies so the result is correct regardless of merge strategy.

## Usage

```
/ro:git-cleanup                    # interactive, asks before deleting
/ro:git-cleanup --dry-run          # show the report, touch nothing
/ro:git-cleanup --base master      # if the repo uses master instead of main
/ro:git-cleanup --include-archive  # include branches named backup/*, archive/*, heads/*
/ro:git-cleanup --yes              # skip confirmation, delete every confirmed-merged branch
```

## Detection strategies

For each local branch (excluding current + base):

1. **Classic-merged**: listed by `git branch --merged <base>`. Deletable with `-d`.
2. **Squash-merged via PR**: `gh pr list --head <branch> --state merged --json number` returns at least one merged PR. The original commits are not in main but the PR was merged. Deletable with `-D` (force).
3. **Content-in-main**: `git diff <base>..<branch>` is empty. The branch's tree is identical to main. Deletable with `-D`. (Rare but possible: branch was rebased to match main without a PR, or the same changes were committed independently on both.)
4. **Unmerged**: none of the above. Skip unless the user explicitly asks.

Branch names matching `backup/*`, `archive/*`, `heads/*` are treated as **archive-intentional** and skipped by default. Include with `--include-archive`.

## Process

### 1. Safety checks

```sh
# Ensure we're in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }

# Working tree cleanliness is NOT required (we're only touching refs, not files)

# Base branch exists
BASE=${BASE:-main}
git rev-parse --verify "$BASE" >/dev/null 2>&1 || { echo "base branch $BASE not found"; exit 1; }

# Stash current state? No: we don't modify the tree. But if current branch is
# about to be deleted (shouldn't happen, we skip current), bail.
CURRENT=$(git rev-parse --abbrev-ref HEAD)
```

### 2. Fetch and prune

```sh
git fetch --prune origin
```

This also removes stale `origin/*` remote-tracking branches whose remote was auto-deleted by `delete_branch_on_merge: true`.

### 3. Classify

Build a table. One row per local branch (excluding `$CURRENT` and `$BASE`):

```sh
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vE "^($CURRENT|$BASE)$"); do
  # Skip archive-ish names unless --include-archive
  if [[ "$branch" =~ ^(backup|archive|heads)/ ]] && [ -z "$INCLUDE_ARCHIVE" ]; then
    status="archive-skip"
  # Strategy 1: classic merge
  elif git branch --merged "$BASE" | grep -qE "^  $branch$"; then
    status="classic-merged"
  # Strategy 2: merged PR on GitHub
  elif command -v gh >/dev/null && gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null | grep -q .; then
    pr=$(gh pr list --head "$branch" --state merged --json number --jq '.[0].number')
    status="squash-merged-pr#$pr"
  # Strategy 3: content in main
  elif [ -z "$(git diff "$BASE..$branch")" ]; then
    status="content-in-main"
  else
    # Check unpushed / ahead state
    ahead=$(git rev-list --count "$BASE..$branch")
    status="unmerged-ahead-$ahead"
  fi
  echo "$status | $branch"
done
```

### 4. Report

Print a grouped summary. Example:

```
Classic-merged (safe, -d deletion):
  - chore/pnpm-pin
  - fix/og-external-fonts

Squash-merged via PR (use -D, PR confirms intent):
  - chore/github-hygiene-and-commitlint (PR #19 merged)
  - test/visual-home-baselines (PR #18 merged)

Content matches main (use -D):
  - feat/rebased-onto-main

Archive-style (kept by convention, use --include-archive to delete):
  - backup/feat-prism-mock-server-pre-split
  - heads/pre-tanstack-migration

Unmerged (NOT proposed for deletion):
  - feat/wip-xyz (3 commits ahead of main)

Stashes on this repo (informational only, not touched):
  - stash@{0}: user-wip-prism-mock (73 minutes ago)
  - stash@{1}: pre-migration-working-state (6 days ago)
```

### 5. Confirm

Use `AskUserQuestion` with 3 options:

- **Delete everything the report proposes** (classic-merged + squash-merged-pr + content-in-main). Recommended.
- **Delete only strictly-merged** (classic-merged only). Safest.
- **Review each individually** (fall back to per-branch yes/no).

Skip the question if `--yes` was passed.

### 6. Delete

```sh
# classic-merged: -d (asserts git thinks it's merged)
git branch -d "$branch"

# squash-merged-pr / content-in-main: -D (force, because git doesn't know)
git branch -D "$branch"
```

Record each deletion and its prior SHA in the final summary, so the user can recover with `git branch <name> <sha>` if a delete was wrong.

### 7. Final summary

Print:

- Count deleted, count kept.
- Any remaining local branches that are `unmerged-ahead-N` (future `/ro:git-cleanup` runs will keep skipping them).
- The stash list, untouched (user may want to decide separately).

## Edge cases

- **No `gh` installed:** skip strategy 2. Classic-merged + content-in-main still work, so the skill is still useful, just misses squash-merged-PR cases where the branch had no patch-equivalent landing.
- **Not logged in to `gh`:** strategy 2 fails silently (its query errors, we treat as "no merged PR"). Report at the end: "gh auth missing, squash-merge detection was skipped, here are the branches that could have been squash-merged that we couldn't verify."
- **Repo has no `origin`:** fetch step no-ops. All detection still works against the local `$BASE`.
- **The current branch is a merged one:** skipped by design (we exclude `$CURRENT`). Print a note suggesting `git checkout $BASE` then re-run.
- **Dirty working tree:** does not block this skill. We don't touch files, only refs.
- **`main` has moved since last fetch:** fetch step at the start prevents stale classification.

## Gotchas

- **`git branch --merged <base>` uses local `<base>`, not `origin/<base>`.** Without the fetch, a branch merged to origin but not pulled locally would be misclassified as unmerged. The fetch step prevents this.
- **`gh pr list --head <branch>` matches the branch name, not the SHA.** If the branch was renamed after the PR merged, detection misses it. Unusual edge case.
- **Force-deleting a branch with unique local work is unrecoverable** unless the SHA is still in the reflog. The skill prints prior SHAs in the final summary so `git branch <name> <sha>` can recover.

## Sibling skills

- `/ro:stacked-prs`: the rebase flow this skill's output enables (once the parent is cleanly merged-and-pruned).
- `/ro:gh-ship`: opens the PR in the first place. Most branches this skill deletes were opened by gh-ship.

## Reference

- ADR covering the squash-only workflow that makes this skill necessary: `connections-helper/docs/adr/0002-github-branch-protection-squash-only-merges.md`.
- llm-wiki concept: `github-branch-protection-and-squash-merges` in `llm-wiki-research`.
