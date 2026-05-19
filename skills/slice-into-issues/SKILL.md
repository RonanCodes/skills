---
name: slice-into-issues
description: Take a PRD (parent GitHub issue OR local prd.json) and slice it into vertical-slice user-story issues that an agent can pull from a Kanban backlog. Defers to /ro:repo-mode for output target — `personal` repos publish each slice as a child GitHub issue referencing the parent via `## Parent\n\n#<N>` with ready-for-agent label; `work` repos write gitignored `.ralph/issues/*.md` so nothing leaks to the work GH/Jira/ADO project. First-run prompt picks the mode and persists per-repo. Use after /write-a-prd or /generate-spec, before /ralph or /ro:planner-worker. Triggers on "slice the prd", "make issues", "break this into stories", "kanban from prd", "vertical slice this".
category: workflow
argument-hint: [--prd <path-or-issue-number>] [--target gh|local] [--label <label>] [--out <dir>] [--max-slices <N>]
allowed-tools: Bash Read Write Glob Grep AskUserQuestion
---

# Slice Into Issues

The missing step between a PRD and a Ralph loop. Matt Pocock's workshop makes this an explicit phase: read the PRD, propose what modules to create or change, then break the work into vertical slices that each touch all the layers they need.

## Output target — repo-mode aware

Resolution order (highest precedence first):

1. Explicit `--target gh|local` flag — always wins.
2. **Repo mode** — defer to `/ro:repo-mode` resolution. Per-repo `.claude/repo-mode`, then global `~/.claude/repo-mode`. If `personal` → `--target gh` (publish each slice as a child GH issue). If `work` → `--target local` (write to `.ralph/issues/*.md`, fully gitignored, nothing leaks to the work GH/Jira/ADO project).
3. If repo mode is `unset`: run the **first-run prompt** described in `/ro:repo-mode` § "First-run prompt". Fires once per repo, then never again.
4. If repo mode resolves but no `gh` remote exists → force `--target local` regardless of mode.

Resolver snippet (same 4 lines documented in `/ro:repo-mode`):

```bash
mode=""
[ -f .claude/repo-mode ] && mode="$(tr -d '[:space:]' < .claude/repo-mode)"
[ -z "$mode" ] && [ -f "$HOME/.claude/repo-mode" ] && mode="$(tr -d '[:space:]' < "$HOME/.claude/repo-mode")"
case "$mode" in personal|work) ;; *) mode="unset" ;; esac
```

### Resolving the parent PRD

The `--prd` argument:

- An integer (e.g., `--prd 798`) → treat as a GH issue number; `gh issue view 798 --json title,body` to load.
- A path (e.g., `--prd .ralph/prd.json` or `--prd docs/prds/foo.md`) → load from disk.
- Omitted → if `--target gh`, list open issues with `ready-for-agent` label whose bodies open with `## Problem Statement` (the parent shape) and ask the user to pick. If `--target local`, fall back to the legacy default of `.ralph/prd.json` or newest in `docs/prds/`.

### Publishing slices to GH

For each approved slice, in dependency order (blockers first):

```bash
gh issue create \
  --title "<slice title>" \
  --label "kind:slice" \
  --label "${LIFECYCLE_LABEL}" \
  ${MODIFIER_FLAGS} \
  --body-file -
```

Lifecycle label rules (per the canonical label system, `~/Dev/ronan-skills/canon/labels.md`):

- Default: `LIFECYCLE_LABEL=needs-grilling` for slices whose ACs are still hand-wavy after the interview. Day-shift will tighten them.
- If the slice's ACs came out concrete in this run (the typical case after a properly grilled PRD): `LIFECYCLE_LABEL=ready-for-agent`.
- If the user explicitly bypassed the grill (`--skip-grill` or interactive override): `LIFECYCLE_LABEL=ready-for-agent` **plus** `needs-grilling-skipped` as a modifier so the reviewer double-checks ACs.

Modifier flags (`MODIFIER_FLAGS`) are added when the slice meets the criterion:

- `--label hitl-likely` if the slice touches ORM, schema migrations, billing, OAuth, secret rotation. Reviewer will probably escalate.
- `--label parallel-eligible` if the slice is file-disjoint from its siblings (planner-worker fans these out).
- `--label repo-lock` if the slice churns lockfiles, schema reset, or top-level config (planner-worker serialises these).
- `--label bug-fix` if the slice begins with a failing test that the implementer makes pass.

`kind:slice` is **always** added. Legacy project synonyms (`Sandcastle` etc.) still work via `--label <name>`; `--label <name>` flag overrides the lifecycle pick.

Body template — Matt Pocock's slice shape:

```md
## Parent

#$PARENT

## What to build

<concise end-to-end description; cover behaviour, not layer-by-layer implementation>

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### Close-the-loop tests (REQUIRED, every story)

- [ ] **Unit:** new pure functions / Zod schemas / DB repo helpers have vitest coverage.
- [ ] **Integration:** any new API route is exercised via vitest with a mocked Nango / D1.
- [ ] **e2e:** ANY user-facing UI route or flow has a Playwright spec that:
  - Navigates to the canonical URL a real user would reach (not just the page in isolation).
  - Walks the full input-to-completion path (no "page renders" without "completing the form does what it should").
  - Asserts redirects land on the right destination (no loops, no 404s).
- [ ] **Live smoke:** the PR description includes a 30-second manual smoke checklist for the reviewer.

## Blocked by

- #$BLOCKER_ISSUE_NUMBER     ← or "None - can start immediately"
```

The `### Close-the-loop tests` subsection is **non-negotiable**. Every slice this skill emits MUST include it verbatim. The lesson behind it is captured at `[[close-the-loop-tests-acs]]` in the wiki — a user story without an e2e AC is a guaranteed leak (the night-shift swarm only implements what it's asked for; it does not invent tests it wasn't told to write).

The downstream planner (`/ro:planner-worker` § "Close-the-loop AC gate") parses the issue body for `### Close-the-loop tests`. If missing it either refuses to dispatch (default) or auto-injects the boilerplate, controlled by the repo-local `.ronan-skills.json` flag `swarm.missing_test_acs: refuse|inject`.

Publishing in dependency order means earlier slices' real issue numbers can be referenced in later slices' `Blocked by` sections. Capture each created issue number as you go.

After publishing, comment on the parent PRD issue:

```bash
gh issue comment $PARENT --body "Sliced into:
- #$SLICE_1 — <title>
- #$SLICE_2 — <title>
..."
```

Do NOT close or modify the parent PRD issue body.

Hand off to `/agentic-e2e-flow` gate 5 (build) or invoke `/ro:ralph --source github:ready-for-agent` directly.

## Why slicing matters

A PRD describes *what* should exist. An agent loop needs to know *in what order, in what chunks*. Bad slicing breaks Ralph in three ways:

1. **Horizontal slices** ("build the whole service first") leave the agent coding blind. No end-to-end runnable thing means no feedback loop.
2. **Too-large slices** put the agent in the dumb zone. Each issue should fit comfortably under ~100K tokens of context (system prompt + relevant code + tests + scratch).
3. **Missing dependency edges** make Kanban impossible. The planner can't find unblocked work if you don't mark blocking relationships.

This skill produces slices that avoid all three.

## Usage

```
/slice-into-issues [--prd <path>] [--out <dir>] [--max-slices <N>]
```

Defaults:
- `--prd`: `.ralph/prd.json` or the most recently modified file in `docs/prds/`. Asks if neither exists.
- `--out`: `.ralph/issues/`. Created if missing.
- `--max-slices`: 12 (keeps the first pass tractable; can re-run for more).

## Step 1: Load the PRD

Read the PRD. Confirm it contains:

- Problem statement
- Solution overview
- User stories
- Testing decisions

If any are missing, stop and tell the user to run `/write-a-prd` first.

## Step 2: Propose the module map

Before slicing into stories, propose which modules will be created or modified. Favour **deep modules** (small interface, large behaviour) over shallow ones. The map looks like:

```
NEW
- services/gamification.ts       (deep: points/levels logic, single export)

MODIFIED
- routes/lessons.ts              (add award-points call after completion)
- routes/dashboard.tsx           (render points + level)
- db/schema/user-stats.ts        (add points, level columns)
```

Present this to the user. Pause for review. The user can edit the map before slicing begins. This is the most important decision in the whole flow; getting the module shape right makes everything downstream easier.

## Step 3: Slice into vertical stories

Each story must satisfy:

- **Touches all relevant layers** (schema → service → UI, where applicable). A story that only modifies one file is suspicious unless the PRD genuinely calls for that.
- **Produces something runnable** at the end. A user (or automated test) should be able to see the slice working end-to-end.
- **Fits in one Ralph iteration**. Rough rule: under 5 files modified, under 300 lines of net change.
- **Has explicit acceptance criteria** (what does "done" look like, what test proves it).
- **Marks blocking dependencies** if any (`blocked-by: 002-add-schema`).

The first slice especially must bring some piece of every layer online so subsequent slices have a working spine to extend.

## Step 4: Write the issue files

One markdown file per slice. Filename convention: `NNN-<kebab-slug>.md`. Frontmatter:

```yaml
---
id: 001-award-points-on-lesson-complete
status: ready
blocks: []
blocked-by: []
module: services/gamification.ts
slice-type: vertical
size: small | medium | large
---
```

Body:

```markdown
# 001: Award points on lesson complete (visible on dashboard)

## User story

When a user completes a lesson, they receive points and see the updated total on their dashboard.

## Acceptance criteria

- [ ] Schema: user_stats table has `points` column (default 0).
- [ ] Service: `awardPoints(userId, amount)` exists in `services/gamification.ts`.
- [ ] Route: lesson-complete handler calls `awardPoints(userId, 10)`.
- [ ] UI: dashboard renders current points total.
- [ ] Test: integration test covers lesson-complete → points-visible round trip.

### Close-the-loop tests (REQUIRED, every story)

- [ ] **Unit:** new pure functions / Zod schemas / DB repo helpers have vitest coverage.
- [ ] **Integration:** any new API route is exercised via vitest with a mocked Nango / D1.
- [ ] **e2e:** ANY user-facing UI route or flow has a Playwright spec that walks the canonical URL, completes the form, and asserts the next-step destination (no loops, no 404s).
- [ ] **Live smoke:** the PR description includes a 30-second manual smoke checklist for the reviewer.

## Notes

- Points amount per lesson is hardcoded to 10 for this slice. Configurability lands in slice 005.
- Use TDD: write the integration test first.
```

## Step 5: Sanity-check the slicing

Before writing files, run the smell tests:

- **Vertical check.** Each story touches more than one layer. Flag any that don't.
- **Tracer-bullet check.** The first 1-3 stories produce something *visible* (not just internal plumbing).
- **Size check.** No single story exceeds the size budget. Split if necessary.
- **Dependency check.** No cycles. If A blocks B and B blocks A, surface the issue.

If any check fails, stop and surface the issue to the user. Don't write a bad slicing.

## Step 6: Report

```
Wrote N issue files to .ralph/issues/:
  001-award-points-on-lesson-complete.md
  002-...
Module map saved to .ralph/module-map.md
First 1-3 stories are tracer-bullet visible: yes
Next step: /ralph --kanban  (or /matt-pocock-coding-workflow continues automatically)
```

## When to re-slice

- The user disagrees with the module map. Edit the map, re-slice.
- The first Ralph iteration reveals the slice was too big or too small. Tune `--max-slices` or split manually.
- The codebase has changed substantially since the PRD was written. Re-read the code, re-slice.

## Cross-references

- Vertical slices vs horizontal → `llm-wiki-ai-research:vertical-slices-tracer-bullets`
- Deep modules → `llm-wiki-ai-research:deep-modules-for-ai`
- Phase N Ralph loop → `llm-wiki-ai-research:phase-n-ralph-loop`
- Close-the-loop tests as a required AC section → `llm-wiki-skill-lab:patterns/close-the-loop-tests-acs`
