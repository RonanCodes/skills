---
name: agentic-e2e-flow
description: High-level end-to-end orchestrator for autonomous feature delivery. Sequences swarm-research → grill-with-docs → write-a-prd → slice-into-issues → swarm-or-ralph → gh-ship. Defers to /ro:repo-mode for output target — `personal` repos publish PRD and slices as GitHub issues using Matt Pocock's agent-native repo pattern; `work` repos run the same pipeline fully local in gitignored `.ralph/` so nothing leaks to the work GH/Jira/ADO project. Use when the user wants to "kick off the matt pocock flow", "run the autonomous agent flow", "agentic e2e flow", "the high-level flow", "the big flow", "the whole flow", "ship this feature autonomously end-to-end", or asks to drive a feature from idea to merged PR without manual hand-offs between phases.
category: workflow
argument-hint: [--build swarm|ralph] [--feature "<short title>"] [--skip-swarm] [--skip-grill] [--label <label>]
allowed-tools: Bash Read AskUserQuestion
---

# Agentic e2e flow

Thin sequencer for the full Pocock-style feature pipeline. This skill does not implement anything itself — it drives the underlying skills in order, with explicit confirmation gates between phases. The user can pause, iterate, or skip any phase.

## When to use

User says any of:

- "kick off the matt pocock flow" / "the pocock flow"
- "autonomous agent flow" / "agent flow"
- "agentic e2e flow" / "e2e agent flow"
- "the high-level flow" / "the big flow" / "the whole flow"
- "ship this feature autonomously end-to-end"
- "drive this from idea to merged PR"

Do NOT use for:

- Quick fixes or one-shot edits (just edit the code)
- Pure research with no implementation intent (run `/ro:swarm` directly)
- Existing PRs that just need to merge (run `/ro:gh-ship`)
- Greenfield app scaffolding (run `/ro:new-tanstack-app` first, then this)

## The pattern this implements

Implements [agent-native-repo-pocock pattern](https://github.com/RonanCodes/llm-wiki-skill-lab-vault/blob/main/wiki/patterns/agent-native-repo-pocock.md) — Matt Pocock's repo shape where:

- GitHub issues ARE the backlog (no `.ralph/` local files when a `gh` remote exists)
- One label, `ready-for-agent` (or per-project synonym), gates the queue
- Parent PRD issue + child slice issues distinguished by body shape: parent opens with `## Problem Statement`, slices open with `## Parent\n\n#<N>`
- `CONTEXT.md` (DDD glossary) and lazy `docs/adr/` ADRs accumulate during `grill-with-docs`
- Agent picks any labelled issue; PRs use `Closes #<slice>` so slices auto-close on merge; parent stays open until all children close

## Pre-flight

### Resolve repo mode FIRST (before any GH probing)

```bash
mode=""
[ -f .claude/repo-mode ] && mode="$(tr -d '[:space:]' < .claude/repo-mode)"
[ -z "$mode" ] && [ -f "$HOME/.claude/repo-mode" ] && mode="$(tr -d '[:space:]' < "$HOME/.claude/repo-mode")"
case "$mode" in personal|work) ;; *) mode="unset" ;; esac
```

- `mode == work` → **work pipeline**: skip every GH-side probe below. PRD goes to `.ralph/<name>/prd.md`, slices to `.ralph/issues/*.md`, build via `/ro:planner-worker --skip-grill` (no `--github`) or `/ro:ralph --source local --kanban`, ship via local commits + branch push only. Phase 0 (drafts inbox) is a no-op in work mode (no `prd:draft` issues to scan). Gate 6 (ship) skips `gh pr` and stops at "branch ready locally — open a PR in your work GH/Azure DevOps/Bitbucket project manually if appropriate".
- `mode == personal` → **personal pipeline** (the GH-issue agent-native flow described below). Continue with the agent-native pre-flight checks.
- `mode == unset` → run the first-run prompt from `/ro:repo-mode` § "First-run prompt", persist, then re-resolve. The auto-suggest is based on `gh repo view --json owner -q .owner.login` (RonanCodes / Simplicity-Labs → personal; anything else → work).

### Personal-mode pre-flight (agent-native shape)

When `mode == personal`, verify the repo is in agent-native shape:

```bash
# 1. gh remote present
gh repo view --json url 2>/dev/null

# 2. ready-for-agent label exists
gh label list --json name | jq '.[] | select(.name == "ready-for-agent" or .name == "Sandcastle")' | head

# 3. CONTEXT.md present (or CONTEXT-MAP.md for multi-context)
test -f CONTEXT.md || test -f CONTEXT-MAP.md

# 4. docs/agents/* scaffolded
test -d docs/agents
```

If any check fails, offer to bootstrap before proceeding:

- Missing `gh` remote → offer `gh repo create` (or suggest the user might want `/ro:repo-mode work` instead if this is actually a work repo)
- Missing label → offer `gh label create ready-for-agent --color FBCA04 --description "Issues queued for autonomous agent"`
- Missing `CONTEXT.md` → tell user this will be created lazily during grill-with-docs
- Missing `docs/agents/` → offer to drop in templates from `~/.claude/templates/docs-agents/` (the templates explain backlog/triage-labels/domain conventions)

The user can skip bootstrap and proceed anyway. The downstream skills tolerate partial setup.

## Phase 0 — Drafts inbox check (pre-flight)

Before generating a fresh PRD in gate 3, check whether the user already has ideas sitting in the `prd:draft` inbox. The inbox is the agent-native repo's "idea capture" — issues labelled `prd:draft` with freeform bodies that have NOT been grilled into Pocock's 7-section template yet.

```bash
gh issue list --label prd:draft --state open --json number,title,url,updatedAt --limit 20
```

If `N >= 1` open drafts, ask via `AskUserQuestion` ONCE (do not be intrusive; if the user already named a feature, default-proceed if they don't pick a draft):

> "You have N open draft PRDs in this repo. Grill one of those, write a fresh PRD, or proceed without checking?"

Options:

- Each draft as its own option: `"Grill #<num> — <title>"` (cap at first ~60 chars of title)
- `"Write a fresh PRD"` (the default — proceeds to gate 1/2/3 as normal)
- `"Proceed without checking"` (skip the question for the rest of this session)

On user pick:

- Pick a draft → route to `/grill <issue-number>` for gate 2; the grill flow rewrites the body into the 7-section template and the user swaps the label from `prd:draft` to the gate label (e.g. `ready-for-agent`). After grill, that issue IS the parent PRD; skip gate 3 (write-a-prd) and proceed directly to gate 4 (slice-into-issues) with `--prd <issue-number>`.
- Write fresh → continue to gate 1 as normal.
- Skip → continue to gate 1 as normal.

If `N == 0`, this phase is a silent no-op — proceed straight to gate 1.

**`prd:draft` issues are NEVER picked up by gate 5 (build).** Drafts are explicitly excluded from `ready-for-agent`-labelled queries downstream. See `/ro:ralph` § "Filter / scope: `prd:draft` is NEVER picked up" and `/ro:planner-worker` § "Filter / scope: `prd:draft` is NEVER picked up" for the gh-query-level guards.

## The flow (six gates)

```
┌─ drafts ─┐  ┌─ swarm ─┐  ┌─ grill ─┐  ┌─ write-prd ─┐  ┌─ slice ─┐  ┌─ build ─┐  ┌─ ship ─┐
│ inbox    │→ │  optl.  │→ │ docs    │→ │  → GH issue │→ │ → GH    │→ │ swarm   │→ │ gh-ship│
│ check    │  │ research│  │ CONTEXT │  │   parent    │  │ children│  │ or ralph│  │  merge │
└──────────┘  └─────────┘  └─────────┘  └─────────────┘  └─────────┘  └─────────┘  └────────┘
  phase 0       gate 1       gate 2         gate 3         gate 4       gate 5      gate 6
```

At each gate, summarise what was produced, ask "ready to proceed, iterate, or skip?". Default action is proceed.

### Gate 1 — Swarm research (optional)

Skip when:
- `--skip-swarm` passed
- Feature is small enough not to need prior-art research
- User already has the design in their head

Otherwise invoke `/ro:swarm --research` (or `/ro:planner-worker --research-mode`) with the feature topic. Output: a short research brief in the conversation context. No files written yet.

### Gate 2 — Grill with docs

Invoke `/grill` (the dispatcher). In an agent-native repo it routes to `grill-with-docs` (Matt's symlinked skill), which stress-tests the plan against the codebase and `CONTEXT.md`, sharpens domain language as you go, and writes lazy ADRs to `docs/adr/` when hard-to-reverse decisions crystallise.

Output side-effects: updated `CONTEXT.md`, possibly new `docs/adr/000N-*.md`.

### Gate 3 — Write PRD → publish as GH issue

Invoke `/ro:write-a-prd`. In a repo with `gh` remote, the skill defaults to publishing the PRD as a GitHub issue using Matt's 7-section template:

```md
## Problem Statement
## Solution
## User Stories
1. As a <actor>, I want <feature>, so that <benefit>
2. ...
## Implementation Decisions
## Testing Decisions
## Out of Scope
## Further Notes
```

Apply the `ready-for-agent` label (or project synonym). Output: a new GH issue number, call it `$PARENT`.

Confirmation gate: show the published issue URL, ask "PRD looks right?".

### Gate 4 — Slice into child GH issues

Invoke `/ro:slice-into-issues`. In a repo with `gh` remote, the skill defaults to publishing each vertical slice as a child GH issue, body template:

```md
## Parent

#$PARENT

## What to build

<concise end-to-end description>

## Acceptance criteria

- [ ] ...
- [ ] ...

## Blocked by

#<sibling-issue-number>     ← or "None - can start immediately"
```

All children get the `ready-for-agent` label. Children are published in dependency order (blockers first) so `Blocked by` can reference real issue numbers.

Confirmation gate: show the children's URLs as a list. User can edit titles/bodies before the build phase starts.

### Gate 5 — Build (swarm or ralph)

Pick by `--build` flag:

- `--build swarm` (default): `/ro:planner-worker --source github:ready-for-agent`. Parallel multi-agent build across worktrees. Best when slices are independent and you want speed. Opus 4.7 is the default merger.
- `--build ralph`: `/ro:ralph --source github:ready-for-agent --reviewer opus`. Sequential single-agent loop with Pocock implementer/reviewer split, Opus 4.7 as the default reviewer. Best when slices are dependency-chained (`Blocked by` graph is mostly linear) or when you want one PR open at a time.

The build skill picks `ready-for-agent`-labelled issues whose body opens with `## Parent` (slices, not the parent PRD), respects `Blocked by`, opens one PR per slice with `Closes #<slice-number>` in the PR body, and labels the issue `in-progress` while working.

On each slice complete, automatic transition to gate 6 for that slice.

**Always fires `/ro:pushover` at the end of gate 5** (done / paused / blocked / crashed) — confirmed 2026-05-14, autonomous build runs always get a phone ping regardless of whether the user typed "AFK" or "night shift". Skip only when `--plan-only` or `--no-ping`.

### Gate 6 — Ship

`/ro:gh-ship` drives each PR through review → merge → deploy-verify. On merge, GitHub auto-closes the linked slice via the `Closes #N` in the PR body. The parent PRD issue stays open.

When all child slices are closed, comment on the parent PRD: "All slices merged. Closing." and close the parent.

## Resume mid-flow

If the flow is interrupted (context switch, sleep, crash), invoke the skill again with `--feature "<title>"`. The skill detects state by:

1. `gh issue list --label ready-for-agent --search "<title>"` → finds the parent
2. `gh issue list --search "Parent #$PARENT"` → finds children
3. Open PRs referencing those children → finds in-flight slices

Pick up at the first incomplete gate.

## Local-file fallback

If no `gh` remote is configured, the flow falls back to local files:

- PRD → `.ralph/prd.json` (write-a-prd's legacy default)
- Slices → `.ralph/issues/*.md` (slice-into-issues's legacy default)
- Build → `/ro:ralph --kanban` (reads `.ralph/issues/`)

User should be warned at pre-flight that they're in fallback mode and offered to `gh repo create` to upgrade.

## Sources

- [agent-native-repo-pocock](https://github.com/RonanCodes/llm-wiki-skill-lab-vault/blob/main/wiki/patterns/agent-native-repo-pocock.md) — the pattern this implements
- [mattpocock/course-video-manager](https://github.com/mattpocock/course-video-manager/issues?q=is%3Aissue%20state%3Aclosed) — 800+ issues shipped via this pattern
- [mattpocock/skills — to-prd](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-prd) — PRD template upstream
- [mattpocock/skills — to-issues](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-issues) — slice template upstream
