#!/usr/bin/env bash
# Emit the planner Agent prompt for /ro:planner-worker.
# Usage: planner-prompt.sh <prd-name> [feedback]
# Reads .ralph/<prd-name>/prd.md and produces the planner instructions on stdout.
set -euo pipefail

PRD_NAME="${1:?usage: planner-prompt.sh <prd-name> [feedback]}"
FEEDBACK="${2:-}"
PRD_PATH=".ralph/${PRD_NAME}/prd.md"

if [[ ! -f "$PRD_PATH" ]]; then
  echo "ERROR: PRD not found at $PRD_PATH" >&2
  exit 1
fi

cat <<EOF
You are the PLANNER agent for /ro:planner-worker.

Read the PRD at ${PRD_PATH}.
Explore the codebase enough to size the work.
Emit a backlog of vertical-slice issues to .ralph/${PRD_NAME}/issues/<NNN>-<slug>.md.

Each issue file MUST have frontmatter:

  id: <zero-padded-3-digit>
  title: <one-line>
  status: ready
  depends_on: []
  estimate: <S|M|L>
  dod:
    - <pnpm test passes>
    - <pnpm typecheck passes>
    - <any extra acceptance check>

Body: 5-30 lines describing what to build + why, file pointers, test plan.

Rules:
- Vertical slices only. No "scaffold the schema" without a UI touchpoint.
- Mark depends_on for hot-file conflicts.
- 3-12 issues for v1. If you'd plan more than 12, split the PRD instead.
- Exit cleanly when issues are written. Do not implement anything.

${FEEDBACK:+## Feedback from previous planning round
$FEEDBACK
}
EOF
