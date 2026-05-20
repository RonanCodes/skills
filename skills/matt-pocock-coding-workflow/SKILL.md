---
name: matt-pocock-coding-workflow
description: End-to-end Matt Pocock coding workflow as a single orchestrated skill. Chains grill-me, write-a-prd, slice-into-issues, ralph, and close-the-loop in order. Asks once at the start whether to run in-the-loop (human reviews per issue) or AFK (full night-shift Ralph). Use when starting a new feature, project, or substantial change and you want the disciplined grill, slice, loop, verify shape instead of jumping straight to code. Triggers on: "build the whole flow", "pocock flow", "matt pocock flow", "matt pocock workflow", "start a new feature", "day shift night shift", "set up night shift", "setup night shift", "kick off night shift", "run night shift", "go night shift", "afk run", "go AFK on this", "let's go AFK", "kick off the loop", "go end-to-end", "run the full flow".
category: workflow
argument-hint: [--afk | --in-loop] [--prd <name>] <feature-or-project>
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# Matt Pocock's Coding Workflow

The full Matt Pocock workflow as one skill. Grill the brief, write the PRD, slice into vertical issues, run the Ralph loop, close the loop.

The point is the *discipline*, not the tools. Each phase is a contract with the next. A loose PRD is fatal for AFK runs. Horizontal slices leave the agent coding blind. Pocock Flow refuses to skip steps.

## Part of the local factory

This is the orchestration spine of the **local factory** — the family of agent-loop skills that run autonomously on Ronan's machine. Siblings: `/ro:ralph`, `/ro:planner-worker` (alias `/ro:swarm`), `/ro:night-shift`, `/ro:day-shift`. They share artefact shape, gitignore rules, and PR conventions. See `/ro:ralph` § "Run artefacts (the canonical shape)" for the canonical reference.

The companion is the **remote factory** — the Factory app (tracked separately) that runs the equivalent flow as a cloud service.

## When to invoke

- New feature, new project, new substantial change (anything bigger than a fix).
- You want the disciplined shape: grill, plan, slice, loop, verify.
- You're about to go AFK and need the contract tight before you do.

Skip for: bug fixes, lookups, single-file edits, anything where the spec is already clear.

## The flow

```
0. Day-shift    → day-shift                      (agent + human grill; only if backlog has open issues)
1. Grill        → grill-me                       (human in chat)
2. Plan         → write-a-prd                    (human + agent)
3. Slice        → slice-into-issues              (agent, human reviews)
4. Choose mode  → in-loop or AFK?                (one question)
5. Loop         → ralph (sequential or kanban)   (agent, mode-dependent oversight)
6. Close        → close-the-loop                 (agent + human spot-check)
```

Each step's output is the next step's input. No step is skippable.

Phase 0 (day-shift) is new as of 2026-05-19. It runs ONLY when the repo has open GitHub issues that may need grilling, promoting, or escalating before the rest of the chain fires. On a greenfield repo with no backlog, skip Phase 0 and start at Phase 1 (grill).

## Filter / scope: `prd:draft` is NEVER picked up

This skill orchestrates Ralph at step 5. **`prd:draft` issues are NEVER picked up** by the underlying Ralph (or planner-worker) loop. Drafts are ideas captured in the agent-native repo's inbox — freeform body, NOT Pocock's 7-section template, NOT yet grilled.

To promote a draft into ready work, the user runs `/grill` on the issue (which is what step 1 of this skill does anyway when given a draft issue number). The `grill-with-docs` flow rewrites the body into the 7-section template, then the user swaps the label from `prd:draft` to the gate label (`ready-for-agent` by default, or the project synonym configured in `docs/agents/triage-labels.md`).

**Tip:** if you're starting this workflow and not sure whether to grill an existing idea or write a fresh PRD, run `/ro:list-draft-prds` first to see the drafts inbox for the current repo. Then step 1 of this skill grills the picked draft instead of starting from a blank prompt.

The downstream Ralph step honours this exclusion via `gh` query filters; see `/ro:ralph` § "Filter / scope: `prd:draft` is NEVER picked up" for the query-level guards.

## Step 0: Day-shift the backlog before chain (when repo has issues)

Probe whether there's an existing backlog to shape:

```bash
open_count=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo 0)
```

If `open_count > 0`, invoke `/ro:day-shift` BEFORE the grill phase. The day-shift skill:

- Partitions issues into `prd:draft` / `ready-for-human` / `blocked-on-human` / `swarm` / `needs-triage`.
- Verifies every `swarm`-labelled issue has the close-the-loop AC block; flips missing ones to `needs-info`.
- Grills `prd:draft` and `needs-triage` issues (max 3 rounds via `AskUserQuestion`) and either promotes them to `swarm` or escalates them to `blocked-on-human` with a named human action.
- Forces a daily check on stale `blocked-on-human` issues.

Why this is Phase 0 and not optional: the night-shift / Ralph chain only ships what the AC list says. If yesterday's `ready-for-human` issue is still parked, the loop ignores it. If a `prd:draft` looks superficially ready, the loop dispatches against an ungrilled spec. Day-shift surfaces those before the chain commits to building anything.

If `open_count == 0` (greenfield repo, no backlog): skip Phase 0 entirely, start at Phase 1 (grill).

See [[night-shift-retro-and-day-shift]] for the full async chain this slots into. The skill defers to `/ro:repo-mode`, so work-mode repos read `.ralph/issues/*.md` instead of `gh issue list`.

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

**Research spikes:** if the PRD needs investigation before (or alongside) implementation — pedagogy research, competitor teardown, an architecture spike — emit those as `kind:research` issues. They route to the research-worker flow in Step 5 (deep research → cited doc in `docs/research/` + LLM wiki, no tests) per [[canon:research-tasks]], and their docs feed the downstream implementation slices.

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
- **Batched-context implementers (regression from 2026-05-12 night shift).** When the loop spawns "do 5 stories" agents instead of one-story agents, the long-running batch agent stalls the harness watchdog on silent thinking between stories. Always pass `--mode fresh` and verify each iteration spawns a NEW Agent tool call. See `/ro:ralph` § Lessons (2026-05-12) for the full pattern.
- **PR-process drift under time pressure.** When stories block on infra, the loop will be tempted to `git push origin main` directly to "unblock". Don't. The audit trail becomes unreadable and CI gating breaks. Every change goes through PR + CI green + squash-merge, including chores.
- **CI not running on PRs.** First-iteration pre-flight: verify the project's CI workflow has both `on: push: branches: [main]` AND `on: pull_request:` triggers. If only `push`, the first story is to add the `pull_request` trigger; otherwise CI cannot gate merges and the whole flow degrades to "merge and pray".

## Cross-references (concepts)

- Day shift / night shift framing → `llm-wiki-ai-research:human-in-the-loop-vs-afk-coding`
- Reviewer/implementer split → `llm-wiki-ai-research:push-vs-pull-coding-standards`
- Vertical slices vs horizontal → `llm-wiki-ai-research:vertical-slices-tracer-bullets`
- Phase N over numbered phases → `llm-wiki-ai-research:phase-n-ralph-loop`
- Smart-zone / dumb-zone sizing → `llm-wiki-ai-research:smart-zone-dumb-zone`
- Deep modules → `llm-wiki-ai-research:deep-modules-for-ai`

## Source

Workshop source-note: `llm-wiki-ai-research:matt-pocock-ai-coding-workflow`
