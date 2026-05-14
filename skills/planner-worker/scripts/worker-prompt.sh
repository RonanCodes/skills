#!/usr/bin/env bash
# Emit the worker Agent prompt for one issue.
# Usage: worker-prompt.sh <prd-name> <issue-id>
set -euo pipefail

PRD_NAME="${1:?usage: worker-prompt.sh <prd-name> <issue-id>}"
ISSUE_ID="${2:?usage: worker-prompt.sh <prd-name> <issue-id>}"
ISSUE_FILE=".ralph/${PRD_NAME}/issues/${ISSUE_ID}-"*.md
WORKTREE=".swarm/worktrees/${ISSUE_ID}"

# Resolve the actual issue file (glob expansion)
ISSUE_PATH=$(ls $ISSUE_FILE 2>/dev/null | head -1)
if [[ -z "$ISSUE_PATH" ]]; then
  echo "ERROR: issue ${ISSUE_ID} not found in .ralph/${PRD_NAME}/issues/" >&2
  exit 1
fi

ISSUE_BODY=$(cat "$ISSUE_PATH")

cat <<EOF
You are a WORKER agent for /ro:planner-worker.

Issue: ${ISSUE_PATH}
Worktree: ${WORKTREE}/

You are pinned to ${WORKTREE}/. Do NOT touch sibling worktrees.

## Issue body (inlined)

${ISSUE_BODY}

## Workflow

1. cd ${WORKTREE}
2. Implement the feature/fix described above
3. Run the DoD commands (.swarm.json dod block, or auto-detected: test + typecheck)
4. Only exit successfully when ALL DoD commands pass
5. Commit on the worker branch with an emoji-conventional message
6. Append a one-line summary to ../../logs/${ISSUE_ID}.log

## Rules

- One commit per logical change; ALL must land before exit
- Do not push (the merger handles that)
- Do not edit issues/, prd.md, or other worktrees
- If you fail DoD after one retry with the failure context, exit "stuck" with a one-line cause appended to ../../logs/${ISSUE_ID}.log
EOF
