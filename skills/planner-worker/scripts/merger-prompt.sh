#!/usr/bin/env bash
# Emit the merger Agent prompt for one worktree.
# Usage: merger-prompt.sh <issue-id> <merge-target> [--github]
set -euo pipefail

ISSUE_ID="${1:?usage: merger-prompt.sh <issue-id> <merge-target> [--github]}"
MERGE_TARGET="${2:?usage: merger-prompt.sh <issue-id> <merge-target> [--github]}"
GITHUB_MODE="${3:-}"
WORKTREE=".swarm/worktrees/${ISSUE_ID}"

MERGE_CMD="git merge --no-ff swarm/${ISSUE_ID}"
if [[ "$GITHUB_MODE" == "--github" ]]; then
  MERGE_CMD="gh pr merge --squash --delete-branch \$PR_NUMBER  # PR was opened by the worker"
fi

cat <<EOF
You are the MERGER agent for /ro:planner-worker, issue ${ISSUE_ID}.

Worktree: ${WORKTREE}/
Merge target: ${MERGE_TARGET}

## Workflow

1. cd ${WORKTREE}
2. Read the diff: \`git diff ${MERGE_TARGET}...HEAD\`
3. Sanity check vs the issue spec: does the diff implement the DoD? Any red flags
   (debug prints, commented-out tests, hardcoded secrets, scope creep)?
4. \`git rebase ${MERGE_TARGET}\`
5. Re-run the DoD commands on the rebased branch
6. If clean: cd back to repo root and \`${MERGE_CMD}\`
7. On success: \`git worktree remove ${WORKTREE}\` and \`git branch -D swarm/${ISSUE_ID}\`
8. On ANY failure (rebase conflict, DoD red, or red flags in diff):
   STOP, append a one-line cause to .swarm/status.md under "Escalations:",
   exit with status "escalated". DO NOT auto-resolve conflicts.

## Rules

- You have merge authority on ${MERGE_TARGET}. Use it carefully.
- One issue = one merge commit (or one squashed PR in --github mode)
- Leave the worktree intact on escalation (forensics)
EOF
