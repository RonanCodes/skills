---
name: pocock-flow
description: End-to-end Matt Pocock coding workflow as a single orchestrated skill. Chains grill-me, write-a-prd, slice-into-issues, ralph, and close-the-loop in order. Asks once at the start whether to run in-the-loop (human reviews per issue) or AFK (full night-shift Ralph). Use when starting a new feature, project, or substantial change and you want the disciplined grill, slice, loop, verify shape instead of jumping straight to code. Triggers on "build the whole flow", "pocock flow", "matt pocock flow", "start a new feature", "day shift night shift", "afk run", "go end-to-end".
category: workflow
argument-hint: [--afk | --in-loop] [--prd <name>] <feature-or-project>
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# Pocock Flow

The full Matt Pocock workflow as one skill. Grill the brief, write the PRD, slice into vertical issues, run the Ralph loop, close the loop.

The point is the *discipline*, not the tools. Each phase is a contract with the next. A loose PRD is fatal for AFK runs. Horizontal slices leave the agent coding blind. Pocock Flow refuses to skip steps.

## When to invoke

- New feature, new project, new substantial change (anything bigger than a fix).
- You want the disciplined shape: grill, plan, slice, loop, verify.
- You're about to go AFK and need the contract tight before you do.

Skip for: bug fixes, lookups, single-file edits, anything where the spec is already clear.

## The flow

```
1. Grill        → grill-me                       (human in chat)
2. Plan         → write-a-prd                    (human + agent)
3. Slice        → slice-into-issues              (agent, human reviews)
4. Choose mode  → in-loop or AFK?                (one question)
5. Loop         → ralph (sequential or kanban)   (agent, mode-dependent oversight)
6. Close        → close-the-loop                 (agent + human spot-check)
```

Each step's output is the next step's input. No step is skippable.

## Step 1: Grill

Invoke `/grill-me`. The grilling step decides what the PRD is allowed to contain. Stop conditions:

- Two consecutive questions return "don't care" or "out of scope".
- The user starts inventing answers rather than revealing them. Mark those as explicit assumptions in the PRD instead.

Do not proceed to step 2 until the user explicitly accepts the resolved decisions.

## Step 2: Plan

Invoke `/write-a-prd --quick` (or `--plan` if the brief needs more structure). The PRD must contain:

- Problem statement
- Solution overview
- User stories as **vertical slices** (each story spans schema, service, UI). Reject horizontal stories ("build the whole gamification service") and ask the agent to re-slice.
- Implementation decisions (tech choices, library picks)
- **Testing decisions** (TDD scope, fixtures, what to mock vs hit real)
- Out-of-scope list (what was explicitly NOT decided)

Pause for the human to confirm the PRD before slicing.

## Step 3: Slice

Invoke `/slice-into-issues`. The slicing skill takes the PRD and:

- Proposes a **module map** (which modules to create or modify; favours deep modules over shallow).
- Emits one markdown file per vertical-slice user story into `.ralph/issues/` (or the project's configured issue directory).
- Marks blocking relationships so the Kanban planner can find unblocked work.

Pause for the human to review the module map and the issue files before looping.

## Step 4: Choose mode

Use AskUserQuestion to ask the user:

> "Run the loop in-the-loop (human reviews per issue) or AFK (full night-shift Ralph)?"

Three answers:

- **In-the-loop.** Ralph runs one issue, exits, the human reviews. Best for new codebases, unfamiliar territory, or when the PRD is borderline.
- **AFK.** Ralph runs the whole queue unattended with a reviewer-gate (Sonnet implements, Opus reviews). Best for known codebases with good feedback loops.
- **Hybrid.** First three issues in-the-loop to calibrate, then switch to AFK if the human is satisfied.

The chosen mode determines step 5's flags.

If the user passed `--afk` or `--in-loop` on the command line, skip this question.

## Step 5: Loop

Invoke `/ralph` with the chosen mode:

- In-the-loop: `/ralph --mode single` (one issue, then stop).
- AFK: `/ralph --mode fresh --kanban --reviewer opus` (Kanban backlog, fresh context per issue, Opus reviewer gate).
- Hybrid: start with `--mode single` x3, then `--mode fresh --kanban` for the rest.

While Ralph runs:

- In-the-loop mode: pause for human after each issue. Show the diff and the test output.
- AFK mode: do not interrupt. The reviewer-gate handles drift; let the loop run to completion.

## Step 6: Close

Invoke `/close-the-loop`. Verifies:

- All issues marked done.
- Tests pass.
- Types check.
- UI works (if the project has a UI surface). Use Playwright check or claude-in-chrome if available.
- Each vertical slice produces something visibly reviewable end-to-end.

If close-the-loop finds failures, surface them clearly. Don't auto-fix in this skill; the user decides whether to loop back or accept.

## Failure modes to avoid

- **Skipping the grill step** because the user "already knows what they want". They don't. Grill anyway, briefly.
- **Accepting horizontal slices** because the agent proposed them. Reject and re-slice.
- **Going AFK on a borderline PRD.** If the grill step left more than two open questions, do not go AFK.
- **Reviewing every commit in AFK mode.** Defeats the point. Trust the reviewer-gate and feedback loops; do the morning review.
- **Silent compaction in long sessions.** Each step should hand off to the next with a clean handoff message. Don't ride one context window through all six steps.

## Cross-references (concepts)

- Day shift / night shift framing → `llm-wiki-ai-research:human-in-the-loop-vs-afk-coding`
- Reviewer/implementer split → `llm-wiki-ai-research:push-vs-pull-coding-standards`
- Vertical slices vs horizontal → `llm-wiki-ai-research:vertical-slices-tracer-bullets`
- Phase N over numbered phases → `llm-wiki-ai-research:phase-n-ralph-loop`
- Smart-zone / dumb-zone sizing → `llm-wiki-ai-research:smart-zone-dumb-zone`
- Deep modules → `llm-wiki-ai-research:deep-modules-for-ai`

## Source

Workshop source-note: `llm-wiki-ai-research:matt-pocock-ai-coding-workflow`
