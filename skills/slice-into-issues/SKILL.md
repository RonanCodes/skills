---
name: slice-into-issues
description: Take a PRD and slice it into vertical-slice user-story issues that an agent can pull from a Kanban backlog. Proposes a module map first (favours deep modules), then emits one markdown file per slice to .ralph/issues/ (or the project's configured directory). Use after /write-a-prd or /generate-spec, before /ralph. Triggers on "slice the prd", "make issues", "break this into stories", "kanban from prd", "vertical slice this".
category: workflow
argument-hint: [--prd <path>] [--out <dir>] [--max-slices <N>]
allowed-tools: Bash Read Write Glob Grep AskUserQuestion
---

# Slice Into Issues

The missing step between a PRD and a Ralph loop. Matt Pocock's workshop makes this an explicit phase: read the PRD, propose what modules to create or change, then break the work into vertical slices that each touch all the layers they need.

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
