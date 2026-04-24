---
name: stacked-prs
description: Rebase a stacked feature branch after its parent PR has been squash-merged. Use when you have a branch B that was built on top of branch A, and A just landed on main (squash-merged). Runs git fetch + git rebase onto main + git push --force-with-lease, so B's diff no longer includes A's flattened commits.
category: development
argument-hint: [--onto <branch>] [--no-push] [--dry-run]
allowed-tools: Bash(git *)
---

# Stacked PRs: rebase-after-parent-merges

One command for the recurring pain point of stacked PRs under a squash-merge + linear-history repo. When PR A squash-merges, the original commits get replaced by one new commit with a different SHA. Any branch B that was built on A still carries A's old commits in its history, which pollutes B's diff until B is rebased onto the new main.

This skill automates the fix.

## Usage

```
/ro:stacked-prs                 # rebase current branch onto origin/main, force-push with lease
/ro:stacked-prs --onto develop  # rebase onto a branch other than main
/ro:stacked-prs --no-push       # rebase locally, stop before pushing
/ro:stacked-prs --dry-run       # show what would happen, don't touch anything
```

## When to use

- Branch B was branched off branch A (not main).
- PR A has merged into main (via squash merge, which is the repo's only option under `/ro:new-tanstack-app`'s branch protection).
- `git log main..B` now shows "A's commits" + "B's commits", and B's GitHub PR diff is wider than it should be.
- You want B's PR to show only B's changes.

## When NOT to use

- You're on main (the skill will refuse).
- The branch was rebased already in the last 30 seconds (no-op; `git status` will tell you).
- A was merged via merge-commit (not squash). In that case B's history already contains A's merged commits and a plain `git pull --rebase` is enough; this skill still works but is overkill.

## Why force-push is safe here

Branch protection only applies to `main`. Feature branches are explicitly allowed to be force-pushed: rebasing IS how you update a stacked PR under the squash model. `--force-with-lease` guards against the edge case where someone else pushed to your branch since you last fetched.

## Process

### 1. Sanity checks

- Current branch is not `main` / `master`. If it is, bail with "you're on the base branch, nothing to rebase."
- Working tree is clean (`git status --porcelain` empty). If not, bail with "commit or stash first."
- `origin` remote exists.
- Upstream tracking branch is set. If not, bail with "branch has no upstream; push it first."

```sh
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE=${ONTO:-main}

[ "$BRANCH" = "$BASE" ] && { echo "on $BASE, nothing to rebase"; exit 1; }
[ -n "$(git status --porcelain)" ] && { echo "working tree dirty; commit or stash"; exit 1; }
git rev-parse --abbrev-ref "$BRANCH@{u}" >/dev/null 2>&1 || { echo "no upstream; git push -u first"; exit 1; }
```

### 2. Fetch fresh state

```sh
git fetch origin
```

### 3. Report what's about to happen

Show the commits that will be replayed + where the base moved to. This is the whole output in `--dry-run` mode.

```sh
echo "Will rebase $BRANCH onto origin/$BASE"
echo "Commits to replay (in order):"
git log --oneline "origin/$BASE..HEAD"
echo "---"
echo "New base: $(git log -1 --oneline origin/$BASE)"
```

If `--dry-run`, exit here.

### 4. Rebase

```sh
git rebase "origin/$BASE"
```

If conflicts fire, abort cleanly and tell the user:

```sh
if [ $? -ne 0 ]; then
  echo "Rebase hit conflicts. Resolve, then run: git add <files> && git rebase --continue"
  echo "To abort entirely: git rebase --abort"
  exit 2
fi
```

### 5. Force-push with lease (unless `--no-push`)

```sh
git push --force-with-lease
```

`--force-with-lease` refuses the push if the remote has commits you haven't seen, catching the rare case where someone else pushed to your branch.

### 6. Show the result

```sh
echo "✅ $BRANCH rebased onto origin/$BASE and pushed"
git log --oneline "origin/$BASE..HEAD"
```

## Gotchas

- **Multi-level stacks (C on B on A):** after A merges, rebase B first (this skill), then rebase C onto updated B. If B hasn't been rebased yet, rebasing C onto main will pull in both B's and A's old commits and confuse git.
- **The rebase drops "A's commits":** that's not a bug. Git sees they're already in main via the squash and skips them. What lands on top of main is only B's unique commits.
- **If the rebase picks fights with an A-era file move:** resolve as you'd resolve any rebase conflict. The conflict is real; A's squashed form reorganised the tree and B depended on the old layout.

## Sibling skills

- `/ro:gh-ship`: opens the PR, watches checks, confirms merge. Run this once B is rebased.
- `/ro:new-tanstack-app`: the scaffold that installs branch protection + squash-only merges. This skill exists because of the constraints that scaffold sets up.

## Reference

- ADR: `connections-helper/docs/adr/0002-github-branch-protection-squash-only-merges.md` (the reasoning behind squash-only + the stacked-PR section).
- llm-wiki concept: `github-repo-hygiene` in `llm-wiki-research`.
