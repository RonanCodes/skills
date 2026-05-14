#!/usr/bin/env bash
# Emit the judge Agent prompt at the end of a cycle.
# Usage: judge-prompt.sh <prd-name> <cycle-summary-file>
set -euo pipefail

PRD_NAME="${1:?usage: judge-prompt.sh <prd-name> <cycle-summary-file>}"
SUMMARY_FILE="${2:?usage: judge-prompt.sh <prd-name> <cycle-summary-file>}"
PRD_PATH=".ralph/${PRD_NAME}/prd.md"

CYCLE_SUMMARY="(no summary yet)"
[[ -f "$SUMMARY_FILE" ]] && CYCLE_SUMMARY=$(cat "$SUMMARY_FILE")

cat <<EOF
You are the JUDGE agent for /ro:planner-worker.

PRD: ${PRD_PATH} (re-read it)
Backlog state: .ralph/${PRD_NAME}/issues/ (re-read all)

## This cycle's summary

${CYCLE_SUMMARY}

## Decision

Reply with exactly one of:

- \`KEEP_GOING\` followed by 1-3 bullets describing what is still missing from the PRD acceptance criteria. Returning KEEP_GOING re-invokes the planner with those bullets to look for missed work.
- \`STOP\` if the PRD's acceptance criteria are met, OR all remaining work is escalated, OR you're going in circles (same issues failing the same way twice).

Hard caps still apply (orchestrator enforces --max-cycles default 10, --max-runtime default 4h) regardless of your verdict.
EOF
