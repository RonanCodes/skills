---
name: ralph
description: Run an autonomous Ralph loop to implement tasks from a PRD in .ralph/ OR from GitHub issues labelled `ready-for-agent` (agent-native repo pattern). Each iteration picks the highest-priority unfinished story, implements it in a fresh isolated context, opens ONE PR per story (squash-merged with `Closes #N` for GH source), validates, and updates progress. Source defaults defer to /ro:repo-mode — `personal` repos read from GitHub issues; `work` repos read from local `.ralph/` only (nothing leaks to the work GH/Jira/ADO project). Supports named PRDs via --prd <name>, Kanban-style local files via --kanban, GitHub-issues source via --source github:<label>, and a reviewer-gate (Matt Pocock implementer/reviewer split) via --reviewer <model>. Modes: --mode fresh (default; one story = one fresh subagent), --mode batched (one context across stories, faster but riskier), --mode single (one story then stop). Use when you want to start the Ralph loop, run ralph, or implement PRD tasks autonomously.
category: development
argument-hint: [--prd <name>] [--source local|github:<label>] [--mode fresh|batched|single] [--kanban] [--reviewer <model>] [--plan-only] [--max-iterations <N>]
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# Ralph Loop

Autonomous coding agent loop based on the Ralph Wiggum technique. Each iteration picks one task from a PRD file under `.ralph/` OR from GitHub issues with a configured label (agent-native repo pattern; see `--source github:<label>`), implements it in a **fresh isolated context** by default, opens ONE PR per story, validates, commits, and updates progress.

## Part of the local factory

Ralph is one part of the **local factory** — the family of skills that run autonomous coding loops on Ronan's own machine. Sibling skills in the same family: `/ro:planner-worker` (alias `/ro:swarm`), `/ro:matt-pocock-coding-workflow`, `/ro:night-shift`, `/ro:day-shift`. They share conventions: PR-per-story, squash-merge, Husky-pre-push as the trust gate, `ready-for-agent` labels as the work queue, the per-repo `.claude/repo-mode` for personal vs work, and the artefact shape described in "Run artefacts" below.

The companion is the **remote factory** — the separate Factory app (tracked elsewhere) that runs equivalent loops as a service. Where the local factory shells out from Ronan's terminal, the remote factory will run the same shape against a controlled cloud environment. The two are designed to share story formats and PR conventions so an issue queued for one is queued for the other.

## Source — repo-mode aware

The `--source` flag picks where stories come from:

- `--source local`: reads from `.ralph/prd.json` (sequential) or `.ralph/issues/*.md` (with `--kanban`). Legacy behaviour. Default for **work-mode repos** (keeps the flow invisible to the work GH/Jira/ADO project) and for repos with no gh remote.
- `--source github:<label>`: reads from open GitHub issues with the given label, e.g. `--source github:ready-for-agent` (or the project's synonym such as `Sandcastle`). Default for **personal-mode repos** with a gh remote.

Auto-detect order when `--source` is omitted:

1. Resolve repo mode via the 4-line snippet from `/ro:repo-mode`:

   ```bash
   mode=""
   [ -f .claude/repo-mode ] && mode="$(tr -d '[:space:]' < .claude/repo-mode)"
   [ -z "$mode" ] && [ -f "$HOME/.claude/repo-mode" ] && mode="$(tr -d '[:space:]' < "$HOME/.claude/repo-mode")"
   case "$mode" in personal|work) ;; *) mode="unset" ;; esac
   ```

2. Resolve repo state:

   ```bash
   has_gh="$(gh repo view --json url 2>/dev/null && echo yes || echo no)"
   has_local="$(ls .ralph/issues/*.md 2>/dev/null | head -1 && echo yes || echo no)"
   ```

3. Pick the default:

   - `mode == work` → **always** `--source local`. Never query GH issues; the agent flow must stay invisible. If `.ralph/` is empty, prompt the user to run `/ro:write-a-prd` first.
   - `mode == personal` AND `has_gh == yes` AND `.ralph/` empty → `--source github:ready-for-agent`.
   - `mode == personal` AND `.ralph/` populated → `--source local` to honour existing work in flight.
   - `mode == unset` → run the first-run prompt from `/ro:repo-mode` § "First-run prompt", persist, then re-resolve.
   - `has_gh == no` → force `--source local` regardless of mode.

User can always override with an explicit `--source` flag.

### GitHub-source iteration

When `--source github:<label>` is active, each iteration:

1. `gh issue list --label kind:slice --label ready-for-agent --state open --json number,title,body,labels`
   (Canonical query per `~/Dev/ronan-skills/canon/labels.md`: `kind:slice + ready-for-agent` is the pickup set. Legacy synonyms like `Sandcastle` are still supported via the `--source github:<label>` override.)
2. **Filter out `prd:draft` issues.** See "Filter / scope: prd:draft is NEVER picked up" below — this is a HARD GUARD.
3. Filter to **slice** issues. `kind:slice` is now load-bearing for this. Skip anything with `kind:prd` (parents are tracking issues).
4. Filter to issues with no unsatisfied `Blocked by` (parse `## Blocked by` section, treat closed referenced issues as satisfied).
5. **Close-the-loop matrix gate.** Parse the body for `### Close-the-loop tests` OR `### Close-the-loop verification matrix`. Behaviour per `.ronan-skills.json` `swarm.missing_test_acs` (`refuse` default; `inject` faster but riskier). Mirrors `/ro:planner-worker` US-2a; see [[close-the-loop-tests-acs]] and [[close-the-loop-verification-matrix]] for the AC shapes. Ralph is serial so there's no auto-split — a slice that fails after retries is marked `needs-human` and the next iteration picks up the queue.
6. Pick the highest-priority unblocked slice (tie-break: lowest issue number).
7. **Lifecycle transition:** swap `ready-for-agent` → `in-progress` on the chosen issue. Both labels are mutually exclusive per canon; do this as one `gh issue edit --add-label in-progress --remove-label ready-for-agent`.
8. Branch off the issue with `gh issue develop <issue-number> --name <slug> --checkout`. This produces the issue→branch dev-link so the PR's `Closes #N` is automatic.
9. Implement in a fresh subagent context (same PR-per-story discipline as `local` mode).
10. Open the PR with `Closes #<slice-number>` in the body — GitHub auto-closes the slice on merge.
11. On PR merge, the issue auto-closes (no lifecycle label needed; closed state = absence of any lifecycle label).
12. **On reviewer reject:** swap `in-progress` → `ready-for-agent` (back into the queue).
13. **On HITL escalation / hard block:** swap `in-progress` → `needs-human` and post a structured comment explaining the human action needed.
14. When the last slice for a parent PRD closes, comment "All slices merged" on the parent and close it.
15. **On retry / blocked / deferred**, append a JSON line to `.swarm/failures.jsonl` (same format as `/ro:planner-worker` US-7) so `/ro:night-shift-retro` can fold the retry count and failure mode into the retro `failures[]` block. Ralph's serial nature means there's no auto-split; the retro tracks retries-before-success as a SYSTEM signal across runs.

`Closes #N` in the PR body is the load-bearing convention — without it, slices don't auto-close and the queue silently grows stale.

### Filter / scope: `prd:draft` is NEVER picked up

**`prd:draft` issues are NEVER picked up by this skill.** They represent ideas captured in the agent-native repo's "inbox", not ready work. Drafts have freeform bodies, NOT Pocock's 7-section template, and have not been grilled. Picking one up would mean implementing against an unfinished spec.

To promote a draft into ready work, the user runs `/grill` on the issue. The `grill-with-docs` flow rewrites the body into the Pocock 7-section template, then the user swaps the label from `prd:draft` to the repo's gate label (`ready-for-agent` by default, or the project synonym like `Sandcastle` / `swarm` configured in `docs/agents/triage-labels.md`).

When querying GitHub for backlog issues, ALWAYS exclude `prd:draft`. `gh` label semantics are tricky here: `--label <gate>` matches issues that have the gate label, but an issue can have BOTH `prd:draft` AND the gate label (e.g. if someone mis-labelled). Defence in depth:

1. Pass `--label <gate>` to scope the initial query.
2. Post-filter the JSON: drop any issue whose `labels[].name` contains `prd:draft`.
3. Equivalently, use `gh issue list --label <gate> --search "-label:prd:draft" ...` to push the exclusion server-side.

Reference the user to `/ro:list-draft-prds` if they want to see what's sitting in the drafts inbox. **Tip:** if you're not sure what's queued vs what's still an idea, run `/ro:list-draft-prds` first to see the inbox before kicking off Ralph.

## Quick Start

```
/ralph                                     # One story, fresh context, then stop (default mode=single)
/ralph --mode fresh                        # Loop indefinitely; each story spawns a NEW subagent (recommended for autonomous overnight runs)
/ralph --mode fresh --max-iterations 5     # Cap at 5 fresh-context iterations
/ralph --mode batched                      # ALL stories in ONE continuous context (faster, riskier; opt-in only)
/ralph --prd phase-2-onboarding-2026-05-06 # Use .ralph/phase-2-onboarding-2026-05-06.json (recommended naming for multi-phase projects)
/ralph --plan-only                         # Show what would be done next (no changes)
```

## Modes

The `--mode` flag is the most important decision. Pick the one that matches your risk tolerance:

| Mode | One iteration = | Use when | Risk |
|---|---|---|---|
| `single` (default) | One story, one fresh context, stop | Interactive dev; you want to review each story before kicking off the next | Low; you're in the loop |
| `fresh` | One story, one fresh subagent (Agent tool with a clean context). Loops until all stories pass or `--max-iterations` hit | Overnight autonomous runs, long-running PRD execution | Medium; subagent budgets are bounded but each story starts clean |
| `batched` | Many stories, ONE continuous context | You explicitly want speed over isolation, AND the stories share so much context that re-loading per story would be wasteful | Higher; context drift compounds across stories. Easy to silently relax PR-per-story. Use ONLY with explicit user permission. |
| `unbounded` | Same as `fresh` but no `--max-iterations` cap | "Run all night, ship as much as you can" | Same as `fresh` plus the wall-clock-budget concern |

**Critical rule**: `batched` mode requires explicit user opt-in via the `--mode batched` flag. It must NEVER be the silent default. The night-shift run on 2026-05-06 silently became batched-mode because the agent decided one-context-many-stories was easier; that's exactly what this rule prevents.

## Kanban mode (--kanban)

By default, Ralph reads a single `.ralph/prd.json` and walks its stories in sequence. With `--kanban`, Ralph reads one markdown file per story from `.ralph/issues/` (produced by `/slice-into-issues`) and picks the highest-priority **unblocked** issue each iteration based on `blocked-by` frontmatter.

Use Kanban mode when:

- The PRD has been sliced into vertical-slice issues via `/slice-into-issues` (or `/matt-pocock-coding-workflow`).
- You want to enable parallel agent execution down the road (Sandcastle-style), where multiple Ralph processes pull unblocked issues concurrently.
- Story ordering depends on blocking relationships, not on a fixed sequence.

In Kanban mode each iteration:

1. Walks `.ralph/issues/*.md`, filters to `status: ready` with no unmet `blocked-by`.
2. Picks the smallest-blast-radius unblocked issue (tie-break: filename order).
3. Implements with the same fresh-context + PR-per-story rules as the default sequential mode.
4. Marks the issue `status: done` on success; updates any issues whose `blocked-by` references this one.

Background → `llm-wiki-ai-research:phase-n-ralph-loop`.

## Reviewer gate (--reviewer <model>)

The reviewer gate adds Matt Pocock's implementer/reviewer split to every iteration.

- **Default: `--reviewer opus`** when running against a real backlog (`--source github:<label>` OR populated `.ralph/issues/`). Confirmed 2026-05-14: the user's Max 20x plan has Opus headroom for review, and the Factory-style flows assume Pocock split is on.
- **Off only when:** `--plan-only`, `--mode single` (one-off story exploration), or user explicitly passes `--reviewer none`.
- **Override the model:** pass `--reviewer sonnet`, `--reviewer haiku`, etc. when you specifically want a cheaper or cross-provider reviewer.

How the split works:

- **Implementer agent** (default: Sonnet 4.6). Lean prompt. Story + relevant code + tests. Pulls coding standards from `~/.claude/skills/coding-principles/` on demand only.
- **Reviewer agent** (the model you passed; default Opus 4.7). Receives the full diff, the original issue's acceptance criteria, and the complete coding-standards content inlined. Returns one of:
  - `merge`: PR can be squash-merged.
  - `request-changes`: implementer gets the reviewer's specific notes and tries again (single retry per iteration).
  - `reject`: issue goes back to `status: ready` with the rejection note on the issue file.

Background → `llm-wiki-ai-research:push-vs-pull-coding-standards`.

Do NOT use `--reviewer` together with `--mode batched`; the implementer/reviewer split assumes fresh context per story.

## Per-story fresh context (recommended)

When `--mode fresh` is selected, each iteration MUST:

1. Read `.ralph/prd.json` to find the next unfinished story
2. Read `.ralph/patterns.md` if it exists (carries cross-iteration learnings)
3. **Spawn a NEW subagent via the Agent tool** with `subagent_type: general-purpose` (or a more specialised type if appropriate)
4. The subagent's prompt is self-contained: includes the story's full EARS criteria, design ref, Definition of Done, a copy of `.ralph/patterns.md`, and an explicit instruction to **record `started` ISO 8601 timestamp before any work** + **record `finished` ISO 8601 timestamp before returning** + **embed both into the progress.txt entry** (see "Progress Report Format" below for the exact shape)
5. The subagent does the work end-to-end: implement, test, commit, push, open PR, watch CI green, squash-merge, mark `passes: true`, append to `progress.txt` (with timestamps)
6. The subagent returns a one-line summary
7. The parent loop reads the summary, then spawns the NEXT story's subagent (if more remain and within `--max-iterations`)

This gives true context isolation: a mistake in story N can't compound into story N+1's implementation.

## PR-per-story (HARD GUARD)

Every story MUST be a single PR. No batching. The acceptance bar:

- Branch name format: `ralph/us-NNN-<slug>` (one US-NNN per branch)
- PR title format: `<emoji> <type>(US-NNN): <title>` with EXACTLY ONE US-NNN id
- PR body MUST start with the story's full EARS criteria
- Squash-merge ONLY (so the merged commit is `<emoji> <type>(US-NNN): <title> (#<pr>)`)

If the implementing agent finds itself wanting to bundle multiple stories into one PR, it must STOP and surface the situation back to the user via `AskUserQuestion`:

```
"Story US-NNN naturally bundles with US-(NNN+1) because [reason].
Bundle into one PR (and split the story IDs in the title), or
keep as two PRs?"
```

The default answer is "keep as two PRs". The agent NEVER bundles silently.

To verify post-merge that the rule held: `gh pr list --state merged --search "(US-" --json title` should show exactly one US-NNN per row. The `/lint --artifacts` skill (when run on a Ralph-produced repo) flags PRs that bundle.

## PRD File Resolution

The `--prd <name>` flag selects which PRD file to work from:

- `--prd <name>` → reads `.ralph/<name>.json` and writes progress to `.ralph/<name>.progress.txt`
- no flag → reads `.ralph/prd.json` and writes progress to `.ralph/progress.txt` (legacy / single-PRD projects)

### PRD naming convention (recommended for multi-phase projects)

When generating a new PRD for a phased project, use the form:

    phase-<N>-<slug>-<YYYY-MM-DD>

so the file is `.ralph/phase-2-onboarding-2026-05-06.json` and the progress file is `.ralph/phase-2-onboarding-2026-05-06.progress.txt`. Sortable by phase, dated for traceability, slugged for readability. Maintain `.ralph/index.md` (one row per PRD: file, status, started-at, finished-at, PR count, summary). Append to the index on every new PRD; update the row on completion.

The `--prd` flag accepts the bare name with or without the `.json` extension; the skill resolves to `.ralph/<name>.json` and `.ralph/<name>.progress.txt` either way.

For one-off / unphased projects (the legacy default), `prd.json` + `progress.txt` still work — don't force the phase convention on a small repo that doesn't need it. Apply the phase form when there's a real Phase 1 / Phase 2 / Phase 3 arc.

This lets one repo drive multiple concurrent phases/initiatives without progress-file collisions. Each named PRD is independent: its own story list, its own branchName, its own progress log.

**Naming convention:** use kebab-case slugs tied to the phase or initiative — `phase-2a`, `phase-2b-presentation`, `auth-migration`, `docs-refresh`. The slug must match `[a-z0-9-]+`.

**Shared Codebase Patterns:** `.ralph/patterns.md` is the single durable knowledge surface — read at start of every iteration, harvested into at loop close.

## Run artefacts (the canonical shape)

Four classes of file, four different lifecycles:

| File | Lifecycle | Git status | Who writes |
|---|---|---|---|
| `.ralph/patterns.md` | Durable, cross-run | **committed** | Orchestrator harvests at loop close. Subagents read at iteration start. |
| `.ralph/<phase>.session.md` | Per-phase rolling aggregate | **committed** | Orchestrator at session start (heading) and loop close (finish line + aggregates). |
| `.ralph/sessions/<session-id>.md` | Per-session detail log, write-once | **committed** | Orchestrator at loop close after harvest. One file per session, per-story sections, post-harvest. |
| `.ralph/sessions/<session-id>/<worker-id>.md` | Per-worker live scratch | **gitignored** | Each worker writes its own file. Survives locally for crash inspection; never committed. |
| `.ralph/<phase>.json` (PRD) | Per-phase spec | committed | Authored manually or by `/ro:write-a-prd` once. |

**Why the split:**

- The local factory runs parallel workers in git worktrees. A single shared append-only progress file is a merge-conflict pinch point — two workers finishing at the same time clobber each other. **Worker scratch is per-worker + gitignored** to avoid that.
- After the orchestrator harvests scratch into `patterns.md` at session close, there's still a per-iteration story worth keeping: timestamps, PR/SHA, the bits that weren't reusable enough to promote. **`sessions/<id>.md` captures that as one committed file per session, written ONCE by the orchestrator** — no append-conflicts (only one writer), no parallel-worker collision (it's written after the workers are done).
- This gives you `cat .ralph/sessions/2026-05-19T01-48-54Z.md` on any machine after `git pull` and you read what happened that night. The full audit lives in git + GH issue threads; this is the indexed quick-read.

**Naming:** the session id is the orchestrator's start ISO slugged (`2026-05-19T01-48-54Z`). The detail log lives AT `.ralph/sessions/<id>.md`; the worker scratch directory is `.ralph/sessions/<id>/`. Same id, different file shape — gitignore distinguishes via trailing slash.

### Worker scratch file shape

Each worker (one per story, in `--mode fresh`) writes to `.ralph/sessions/<session-id>/<worker-id>.md`. The session id is the orchestrator's start timestamp slugged (e.g. `2026-05-19T01-48-54Z`). The worker id is the story id (`us-128`). Contents are short:

```
# Worker scratch — US-128

started: 2026-05-19T01:49:30+02:00
finished: 2026-05-19T02:01:52+02:00
duration: 12m22s
pr: #138 (squash-merged 55e10e0)

## Learnings (for patterns.md harvest)
- <one or two lines a future story would want to know>
- <a gotcha that should not happen again>

## Files changed (informational, already in git)
- src/lib/server/spaced-rep.ts
- src/lib/server/__tests__/spaced-rep-cap.integration.test.ts
```

The "what was implemented" prose lives in the PR body — don't duplicate it here.

### Orchestrator's harvest step at loop close

When the loop exits (cleanly, max-iterations, or hard error), the orchestrator MUST:

1. Read every `.ralph/sessions/<session-id>/*.md` file written during the session.
2. Promote any reusable learnings into `.ralph/patterns.md` under an existing or new section heading. Skip per-story / PRD-specific gotchas — those keep going but in the session detail log, not patterns.
3. Write the per-session detail log to `.ralph/sessions/<session-id>.md`. One section per story, structure:
   ```markdown
   # Session <id> detail — <phase>

   <session-level metadata: mode, reviewer, total stories, total duration>

   ## US-NNN: <Story Title>
   - started: <ISO> / finished: <ISO> / duration: <Nm Ns>
   - PR: #<n> (squash-merged <sha>) → Closes #<issue>
   - What shipped: <one paragraph from the worker scratch + PR body>
   - Promoted to patterns.md: <yes/no — and which section if yes>
   - Local learnings (not promoted): <story-specific gotchas worth keeping for one cat-and-read but not worth carrying forward>

   ---
   ```
4. Write the session aggregate to `.ralph/<phase>.session.md` (see "Session timing" below) — that's the rolling per-phase summary; the detail log above is the per-session deep-dive.
5. Commit `patterns.md` + `sessions/<id>.md` + `<phase>.session.md` together as a single `🧹 chore(ralph): session <id> artefacts for <phase>` commit. Fresh `chore/ralph-session-<id>` branch is fine, or directly on `main` if the run was purely on main.
6. Leave the per-worker scratch directory in place locally so the operator can read it; it's gitignored and will be cleaned up on the next session start (or never — disk is cheap).

### Gitignore policy (no longer prompted)

The new default is fixed:

```gitignore
# Ralph / local-factory artefacts.
# Per-worker scratch directories under .ralph/sessions/<id>/ are ignored;
# the per-session detail log .ralph/sessions/<id>.md (sibling file) stays tracked.
.ralph/sessions/*/
.ralph/*.progress.txt
.ralph/.gitignore-policy
```

The trailing slash on `.ralph/sessions/*/` is load-bearing: `*/` matches only subdirectories, so `.ralph/sessions/<id>/<worker>.md` is ignored while `.ralph/sessions/<id>.md` stays committed.

`patterns.md`, `<phase>.session.md`, `sessions/<id>.md`, and `<phase>.json` (PRDs) stay tracked. The first-run policy prompt is retired — the shape is now standard across the local factory.

For legacy projects that already have a committed `.ralph/progress.txt`: leave it in git history for the audit trail, gitignore the path going forward, and write a follow-up `🧹 chore(ralph): retire legacy progress.txt, harvest learnings into patterns.md` commit that deletes the file from main and copies any surviving learnings into `patterns.md`.

## How It Works

0. Ensure `.gitignore` carries the local-factory artefact rules (see "Gitignore policy" above); add the three-line block if it's missing
1. **Record session start** by writing the `## Session N` heading to `.ralph/<name>.session.md` with timestamp + flags. Compute the session id (start ISO slugged) and create `.ralph/sessions/<session-id>/` for worker scratch files.
2. Resolve PRD file from `--prd` flag (or default `.ralph/prd.json`) — find the highest priority story where `passes: false`
3. Read `.ralph/patterns.md` (the durable knowledge surface) — every iteration reads it
4. **Record story start** timestamp in the orchestrator's notes (passed to the subagent prompt so the worker echoes it back into its scratch file)
5. **In `--mode fresh`: spawn a fresh subagent for this story.** In `--mode batched`: continue in current context. In `--mode single`: do this story then stop.
6. Implement the story against the EARS acceptance criteria
7. Validate (typecheck, lint, test — whatever the project requires; respect Definition of Done if present in the spec)
8. **Open ONE PR for this story** (no batching; see PR-per-story HARD GUARD above)
9. Commit with message: `<emoji> <type>(US-NNN): <Story Title>`. Weekday timestamps must fall outside 08:30–18:00 (CLAUDE.md rule) — pass `GIT_AUTHOR_DATE` + `GIT_COMMITTER_DATE` to git commit if running inside that window.
10. Wait for CI green; auto-merge via squash
11. **Record story finish** timestamp; compute duration; subagent writes its scratch file at `.ralph/sessions/<session-id>/<worker-id>.md`
12. Update the PRD file — set `status: "passed"`, `passes: true`, and `notes` including the squash SHA
13. Worker returns its one-line summary to the orchestrator
14. **On loop exit** (all stories complete OR max-iterations OR hard error): orchestrator runs the harvest step (see "Orchestrator's harvest step at loop close" above): promotes reusable learnings to `patterns.md`, writes the per-session detail log to `.ralph/sessions/<session-id>.md`, finalises `.ralph/<name>.session.md` with finish-line + aggregates, commits the three files as one `chore(ralph): session <id> artefacts for <phase>` commit

## One Story Per Iteration (in fresh / single modes)

In `--mode fresh` and `--mode single`, work on ONE story per iteration. After completing it:

- `single`: stop. Next `/ralph` invocation picks up the next story.
- `fresh`: spawn a NEW subagent for the next story (until `--max-iterations` or all stories pass).

In `--mode batched`, multiple stories share one context. This is the explicit opt-in for situations where the user accepts the risk in exchange for speed.

## Always fire completion-report + Pushover at end (load-bearing default)

ANY `/ro:ralph` run against a real backlog ends with TWO tail calls, in this order:

1. **`/ro:completion-report --prd <name> --no-open`** — writes a browsable HTML report to `<repo>/.completion-reports/<ts>-<prd>.html` with per-PR cards, file diffs, per-file rollback commands, and a risk panel. Capture the absolute path it prints.
2. **`/ro:pushover --url file://<path-from-step-1>`** — sends the done / paused / blocked / crashed ping with the report path as a deep link, so tapping the phone notification opens the report.

If step 1 reports an empty range ("no commits in range, nothing to report"), skip the `--url` flag on step 2 but STILL send the ping with the state message.

Skip BOTH tail calls ONLY when:

- `--plan-only` (nothing actually ran)
- `--mode single` and it's the only story (one-shot exploration, not a real run)
- User explicitly passed `--no-ping`

For the recipes: report path printing in `~/Dev/ronan-skills/skills/completion-report/SKILL.md`; Pushover firing in `~/Dev/ronan-skills/skills/pushover/SKILL.md`. Message shape: state + one concrete metric + what Ronan needs to do next. Example: `"ralph done — 14/14 stories merged, 0 deferred, ready for visual review"` with the report URL attached.

## Worker scratch format (replaces the old progress.txt)

Each worker writes one scratch file at `.ralph/sessions/<session-id>/<worker-id>.md`. Files are gitignored — they die at session close after the orchestrator's harvest step (see "Orchestrator's harvest step" above). The shape:

```
# Worker scratch — US-128

started: 2026-05-11T23:35:12+02:00
finished: 2026-05-11T23:44:41+02:00
duration: 9m29s
pr: #61 (squash-merged 8240af6)

## Learnings (for patterns.md harvest)
- <one or two lines a future story would want to know>
- <a gotcha that should not happen again>

## Files changed (informational)
- path/one.ts
- path/two.tsx
```

Both `started` and `finished` are real wall-clock ISO 8601 timestamps with offset, NOT the backdated git commit dates. The subagent records `started` first thing after reading its prompt (capture via `date -u +%Y-%m-%dT%H:%M:%S%z` or the local-tz equivalent), and `finished` right before it returns its one-line summary. `duration` is computed in the implementer subagent and embedded.

The "What was implemented" prose lives in the PR body — don't duplicate it here. The Learnings section is the only part the orchestrator's harvest step cares about; everything else exists for the operator reading the scratch directory locally.

## Session timing

`.ralph/<name>.session.md` is a per-PRD session log that tracks loop-level start/finish across all iterations. Format:

```
# Ralph session log — <phase name>

## Session 1 — 2026-05-11T23:33:00+02:00 to 2026-05-12T03:42:18+02:00 (4h 09m 18s)
- mode: fresh
- reviewer: opus
- max-iterations: 12
- stories attempted: 7
- stories passed: 7
- stories deferred / blocked / failed: 0
- total subagent wall-clock: 3h 31m 04s
- orchestrator overhead (between iterations): 38m 14s
- notes: <one or two lines if relevant>

## Session 2 — ...
```

When the loop starts, append a new `## Session N` heading with the start timestamp + flags. When the loop exits (cleanly OR via error OR via max-iterations), edit the session entry to add the finish timestamp + duration + per-story aggregates. If the orchestrator session dies mid-loop (token limit, user disconnect), leave the start timestamp in place; the next `/ralph` invocation appends a new session heading and the prior one is recognisable as "started but never recorded a finish".

Compute the per-story aggregates by summing each worker's `duration` field across the session's scratch directory; the orchestrator does that during the harvest step at loop-exit time.

Total wall-clock and orchestrator-overhead can both be derived: total = `finished - started` from the session line, subagent-sum from the per-worker durations, orchestrator-overhead = total minus subagent-sum.

The session log is committed (it's small, write-once, and conflict-free because only the orchestrator writes it).

## Codebase Patterns (the durable knowledge surface)

`.ralph/patterns.md` is the single document where carried-over knowledge lives. Read at start of every iteration; written into only at session close by the orchestrator's harvest step.

What goes in:

- Reusable patterns: "Auth helper lives at X, server fns use Y shape, tests live at Z."
- Gotchas that would trip any future story: "Cloudflare Workers `crypto.subtle` doesn't support MD5; use `node:crypto` createHash via nodejs_compat."
- Shape decisions: "Drill components carry `data-testid` for Playwright. Pattern is `<drill-type>-<role>`."

What stays out:

- Per-story prose ("US-128 raised the cap to 200") — that's the PR title + body.
- Per-iteration timestamps — those live in the worker scratch + the session.md aggregate.
- Speculative "future ideas" — those are GH issues, not patterns.

Shape:

```markdown
## Codebase Patterns

- Skills use SKILL.md format with YAML frontmatter
- Vault CLAUDE.md files are thin config, not logic
- Use wikilinks [[page]] syntax for cross-references
- Cloudflare Workers `crypto.subtle` does NOT support MD5; use `node:crypto.createHash('md5')` via nodejs_compat
- Drill components carry stable `data-testid` hooks; e2e specs select on those, not class names
```

If `.ralph/patterns.md` does not exist, create it on first use (an empty `## Codebase Patterns` section is fine). Legacy projects with a `## Codebase Patterns` section at the top of `.ralph/progress.txt` should migrate that section into `patterns.md` and gitignore the progress file (see "Gitignore policy" above).

## Stop Condition

After completing a story, check if ALL stories have `passes: true`.

| Mode | When to stop |
|---|---|
| `single` | After 1 story (always) |
| `fresh` | When all stories pass OR `--max-iterations` hit OR a story fails after 3 retries |
| `batched` | When all stories pass OR a hard error |
| `unbounded` | When all stories pass OR a hard error (no iteration cap) |

Report "All tasks complete!" and stop on success. On hard error, report the failed story + reason and exit; the user can resume with another `/ralph` invocation.

## Lessons learned (from real Ralph runs)

This section captures patterns observed in production Ralph runs that future invocations should respect. Add to it after each meaningful run.

### 2026-05-06: Dataforce Phase 1 night shift

Run shape: `--mode batched` (silently, due to skill ambiguity at the time). 17 stories shipped across 6 PRs in 65 minutes via one continuous context.

What went well:
- High coverage in low wall-clock
- Real PRs, real CI, real merges
- Spec-driven autonomy worked: agent rarely needed clarification

What went badly:
- Silent contract relaxation: PR-per-story collapsed into PR-per-batch (one PR covered 6 stories). User couldn't easily audit individual story implementations afterwards.
- No fresh-context isolation: assumptions made in early stories compounded into later ones without anyone noticing. Stub-shaped implementations slipped through (Clerk SSR; OAuth device flow).
- CI green was achieved partly via `continue-on-error: true` on the deploy step. Green-CI signal was misleading.
- Pre-flight didn't catch a revoked Cloudflare token; agent worked around it instead of stopping.

What we changed in the skill (this version):
- `--mode` flag with explicit semantics; `batched` requires opt-in; `fresh` is the recommended autonomous mode
- PR-per-story is now a HARD GUARD with detection + AskUserQuestion if a bundle is tempting
- `Lessons learned` section (this one) so future runs inherit the wisdom
- Recommend running `/spec-to-repo` with its full pre-flight first, before `/ralph`, to catch revoked tokens etc. before the autonomous loop starts

### 2026-05-06: Dataforce Phase 1 morning fix-up — baseline-checklist gap

After the Phase 1 build, the user surfaced six gaps that should have been stories from day one but were one-liner mentions in ADRs the agent didn't translate to user stories:

- Logout button on every authenticated page
- OpenAPI 3.1 spec served + Scalar viewer at /api-docs
- Bruno collection committed for every public route
- Vitest integration tests against an in-memory DB
- Lazy auth-mirror for the cold-start-before-webhook path
- CI workflow writing `.dev.vars` from secrets so the e2e dev-server boots

Each became a follow-up PR. Root cause: the spec mentioned them in ADRs / DoD bullets, but didn't emit them as US-* stories, so Ralph never had a story-shaped target to build against.

Mitigation upstream: `/generate-spec` and `/write-a-prd` now ship a **Web-app baseline checklist** (sign-in/sign-out UI, lazy auth-mirror, API discoverability, API client collection, integration test layer, CI env injection, per-story deploy verification). Any web-app spec missing one of these gets called out before story generation. See [[ideal-tech-setup#Greenfield Spec Baseline (must-have stories)]] for the canonical list.

What Ralph should do now: **before iterating any spec**, scan US-* titles for the baseline checklist. If any are missing in a web-app spec, stop and ask the user via AskUserQuestion whether to add them or mark "N/A — <reason>" before starting.

### 2026-05-06 (afternoon): Dataforce Phase 2 — subagent unavailability + status-field gap

Phase 2 (11 stories) ran in `--mode fresh` but the Agent/Task tool was NOT available inside the spawned Ralph subagent's context, so the per-story-fresh-subagent pattern collapsed into single-agent execution. Result: 6 of 11 stories shipped (the smaller ones), 3 deferred (UI-heavy: onboarding checklist Home, OAuth device flow, Connections polish), 2 blocked-on-human.

What we changed in the skill (this version):

- **Tool availability check**: at start-of-loop, Ralph MUST verify the Agent tool is callable before claiming `--mode fresh`. If unavailable, downgrade automatically to `--mode batched` AND surface a warning, OR refuse to start if the user explicitly asked for fresh and the tool is missing. Don't silently single-agent through 11 stories.
- **Story `status` field**: PRD JSON now uses `status: "passed" | "deferred" | "blocked-on-human" | "blocked-on-code" | "not-started"` instead of bare `passes: bool`. `passes:bool` stays as a derived view (passed === true) for back-compat. Free-text `notes` is for the *why*, not for distinguishing the *kind* of incomplete.
- **Drizzle journal cleanup**: when discarding a generated migration mid-iteration, edit `drizzle/meta/_journal.json` to drop the entry too. Otherwise the next `db:generate` numbers from the stale max idx.
- **Pre-format pass**: at start-of-loop, run `pnpm format:write` once and commit any unrelated touch-ups as a separate `🔧 chore:` commit. Otherwise per-story PRs drag in unrelated whitespace via lint-staged.
- **Deployed-route e2e helper**: stories with a "deployed URL returns 200" DoD criterion need a Playwright config that boots a signed-in browser context against prod (or a session-cookie helper). Without it, "verify deployed" defaults to a curl probe, which doesn't cover routes behind auth. See `[[ideal-tech-setup]]` § Greenfield Spec Baseline for the canonical pattern.

These mitigations apply going forward; Phase 3 PRD must reflect them.

### 2026-05-11 (evening into night): Dataforce Phase 4 + Phase 5 night shift — timestamp gap

Phase 4 (7 stories) + Phase 5 (7 stories) shipped over one continuous night-shift orchestration. `--mode fresh --reviewer opus` worked as designed: 14 fresh subagents (one per story), each spawning a SECOND fresh Opus subagent for review. Zero rejections, zero deferrals. Per-story subagent wall-clock ranged 8m–34m (median ~12m).

What went wrong:
- **No absolute timestamps were recorded.** Only `duration_ms` came back via task notifications, and git commit dates were backdated to honour the weekday-outside-work-hours rule, so the user could not audit when each story actually ran. The progress.txt entries only had a date prefix (e.g. `## 2026-05-11 - US-407: ...`), not a real wall-clock start/finish.
- **Orchestrator briefly committed to the wrong branch.** Between iterations the orchestrator wrote `.ralph/night-shift-state.md` and ran `git add + commit` in the shared working tree, which was at that moment checked out to the subagent's `ralph/us-NNN-...` branch. The commit landed on the subagent's branch and traveled with its PR. Annoying, not broken.

What we changed in the skill (this version):

- **Mandatory timestamps in the progress.txt entry**: `started`, `finished`, `duration`. Subagent records both via `date -u +%Y-%m-%dT%H:%M:%S%z` (or local-tz equivalent) at the very start of work and immediately before returning. The orchestrator does NOT compute or merge times; the subagent owns both fields. See "Progress Report Format" for the exact shape.
- **Per-session log file `.ralph/<name>.session.md`**: a separate per-PRD log that captures loop-level start + finish + flags + per-story aggregates. Survives orchestrator session death (start timestamp recorded eagerly; finish timestamp added at loop-exit, OR recognisably absent if the orchestrator died mid-loop).
- **Orchestrator must never touch the shared working tree between iterations.** Once a subagent has checked out its `ralph/us-NNN-<slug>` branch in the shared repo, the orchestrator's only safe operations are: read PRD JSON files, read progress.txt files, spawn the next subagent. Any git operation the orchestrator wants (e.g. committing a session-state file to main) must be queued for after the loop completes, OR done by a dedicated subagent.

### 2026-05-12 → 2026-05-13: Lekkertaal Phase 1 night shift — background-agent watchdog kills + PR-process drift

Run shape: project scaffolded from PRD with ~35 Phase 1 stories. First batch (7 drill stories) shipped cleanly. Subsequent 5 batch-agent attempts ALL stalled with no merges. After much diagnosis, switched to orchestrator-spawns-fresh-implementer-per-story (the documented `--mode fresh` pattern) and shipped.

What went wrong:

- **Background-agent stream watchdog (600s).** The Claude Code background-agent harness kills any agent that goes 600 seconds without printing to stdout. **Agent thinking time counts as silence.** Batch agents trying to do 7-stories-in-one-context spent >10 min "understanding" the codebase / planning the next story between tool calls and got killed. The harness watchdog is not user-disable-able; the only mitigation is keeping the agent's stream chatty.

- **Earlier batch agents falsely claimed `Agent` tool was unavailable.** When asked to spawn fresh subagents per story, the previous-night agent reported "no Agent/Task sub-agent spawning available in this harness" and pivoted to serial in-context implementation, which then hit the watchdog. The Agent tool IS available to background-spawned agents; it just needed an explicit instruction to use it. (This contradicts the 2026-05-06 Dataforce afternoon finding — that was a different harness configuration.)

- **PR-process discipline drift.** Under time pressure the orchestrator (and I, the calling agent) started direct-pushing to main with `git push origin main` to bypass the PR + CI flow. By the time we caught it, 5 direct-to-main commits had landed and the audit trail was muddled. Worse, the CI workflow only triggered on `push` to main — not on `pull_request` — so PRs had no checks to gate merges with.

- **Cloudflare Workers env-at-init-time trap.** `clerkMiddleware()` and similar middleware called at module init time on CF Workers cannot read secrets via `process.env` (always empty on workers) or via `import.meta.env.*` for non-`VITE_*` keys. They CAN read public `vars` from `wrangler.jsonc`. Forgetting this and registering middleware that reads `CLERK_PUBLISHABLE_KEY` at module init crashed cold-start with 500 on every route, including `/`. Hours lost.

- **Route handlers throwing instead of redirecting.** Several scaffolded auth-gated routes threw `new Error("Not signed in")` when `auth().isAuthenticated === false`. TanStack Start surfaced this as a 500, not a 302 to `/sign-in`. Story implementers must use `throw redirect({ to: '/sign-in' })` from `@tanstack/react-router` for auth gates; never `throw new Error()`.

What we changed in the skill (this version):

- **Watchdog discipline section (mandatory for every subagent prompt)**: subagent MUST echo a heartbeat `echo "[$(date +%H:%M:%S)] <what we're doing>"` BEFORE every Bash call that might take >30s. AND immediately after returning from each long step. Multiple echoes are free; agent-thinking-time-between-tool-calls is the killer.

- **Orchestrator-spawns-fresh-implementer pattern, explicit**: orchestrator does NOT touch code. Its only loop is: (1) read PRD, (2) pick next unfinished story, (3) `Agent` tool call with a self-contained implementer prompt (background=false, blocking), (4) wait for one-line return, (5) log to progress.txt, (6) next story. Implementer is short-lived (~10-20 min) and well under the watchdog. Orchestrator stays cheap in context because its work-per-iteration is just dispatch.

- **PR-only flow is a HARD GUARD**. No `git push origin main`. No `--admin` flag on `gh pr merge`. CI must run on `pull_request:` events (not just `push: branches: [main]`) — verify the project's workflow has both triggers BEFORE starting Ralph; if it doesn't, the first story must add a `pull_request` trigger to the workflow. CI passing is required before squash-merge.

- **First-iteration pre-flight**: before any story, scan the project's `.github/workflows/*.yml` for `on: pull_request:`. If missing, story 0 is "Add pull_request trigger to CI workflow". Without this, Ralph cannot enforce CI-gated merges and the whole flow degrades to "merge and pray".

- **CF Workers + Clerk gotcha**: when an upstream story requires Clerk middleware on CF Workers, add `CLERK_PUBLISHABLE_KEY` AND `VITE_CLERK_PUBLISHABLE_KEY` to `wrangler.jsonc` vars (publishable keys ship to browsers; safe to commit). Push `CLERK_SECRET_KEY` as a secret. Same pattern works in `@tanstack/react-start` and `next.js` on CF Workers. Reference implementation: `~/Dev/ai-projects/dataforce/src/start.ts`.

- **Auth gate pattern**: server functions that gate on auth must `throw redirect({ to: '/sign-in' })` (TanStack Router import), never `throw new Error()`. Add this as a Codebase Pattern automatically detectable by scanning `src/lib/server/*.ts` for `throw new Error("Not signed in")` and similar.

- **"Ship simpler with TODO" rule**: when an implementer hits an API it doesn't understand after 5 min of investigation, ship the simpler working version with `// TODO(refinement): <thing>` and move on. The watchdog will kill an agent that spends 15 min reading SDK docs silently.

- **Failure pattern recognition**: if 2 consecutive subagent dispatches stall at the SAME story, escalate — either the story spec is bad or there's an environment issue. Don't retry a third time blindly. Mark the story BLOCKED with the failure reason and continue.

### 2026-05-14: Dataforce Phase 8 — GitHub Actions billing wall blocked overnight merges

Run shape: 6 PRs queued for the merge orchestrator (`/tmp/merge-stack-v4.sh`); first PR merged at 22:48. The remaining 5 sat for an hour because every E2E job died in 3-10s with the annotation:

> The job was not started because recent account payments have failed or your spending limit needs to be increased.

The Quality job (smaller, fits the free tier) ran fine. E2E (longer) needed paid minutes that were unavailable. The orchestrator polled green CI forever and never advanced.

What went wrong:

- **Persistent CI failure looked like flake.** The orchestrator's poll loop has no notion of "this CI will never go green," so it kept waiting.
- **No notification.** The operator was AFK; the run silently stalled. Each lost hour is irrecoverable on a night shift.

What we changed in the skill (this version):

- **Billing-wall detection in the orchestrator.** When `gh pr checks <pr>` shows a FAILURE check AND `gh run view <run-id>` annotation contains "recent account payments have failed" OR "spending limit", the orchestrator stops polling that PR and switches to the **local-CI fallback** path:
  1. Send a `PushNotification` once per orchestrator run, naming the billing URL + the org.
  2. For each remaining PR in queue: checkout the branch locally, run `pnpm install --frozen-lockfile && pnpm db:migrate:local && pnpm run quality && pnpm test:e2e`. If green, `gh pr merge <pr> --squash --delete-branch --admin` with a comment quoting the billing block.
  3. The `--admin` flag is the deliberate exception to the "PR-only flow is a HARD GUARD" rule above. It is permitted ONLY when (a) the local quality+E2E run passed on the branch tip, (b) the PR comment explaining the billing fallback was posted, and (c) the operator was notified.
  4. Subsequent PRs in the queue get rebased onto the new main + force-pushed (same as the normal post-merge rebase step). CI may still try and fail; that's OK because the next merge follows the same local-CI path.
- **Local-drain script lives at `/tmp/local-drain.sh`** as a canonical pattern; reference implementation in this session.
- **Pre-push Husky hook is the first defence.** The pre-push runs `pnpm run quality` already. The billing-fallback ALSO runs `pnpm test:e2e` (which pre-push does not) because E2E is the part GH Actions usually owns. Without this, the local-CI fallback would have a coverage gap vs the real CI.
- **PushNotification mandatory on billing detection.** Single message naming the URL + the affected PRs so the operator can fix billing while the orchestrator keeps draining locally.

This is the only sanctioned way to skip a GH Actions CI gate. Any other "CI is being slow" excuse must wait it out; the only signal that justifies `--admin` is the literal "recent account payments have failed" annotation.

### 2026-05-14 (afternoon): Dataforce Phase 9 — local-CI gate refinements

Two follow-up lessons from running the billing-fallback path repeatedly:

- **Pre-existing main-side failures must NOT block unrelated PRs.** When the local E2E run fails on tests that ALSO fail on the current `main` (verified via `git checkout main && pnpm test:e2e <spec>` or by inspecting the test diff), file the failure as a separate issue and proceed with the merge. The local-CI gate's job is to catch *new* regressions, not to stop unrelated PRs while a pre-existing bug is unresolved. The PR comment quoting the billing block should also enumerate the pre-existing failures and link the tracking issue.

- **Use `test.fixme()` to clear the queue when a deterministic regression lands on main.** When a regression lands and starts gating every subsequent PR's local-CI run, the immediate ship the orchestrator does is a one-line `test.fixme(...)` PR with a comment linking the tracking issue, so the queue can drain. The real fix follows as a separate PR. Marking with `fixme` (not `skip`) keeps the test visible in suite output as a known-broken case rather than silently absent.

- **`gh pr merge --squash --admin` occasionally fails with `invalid character '{' after object key:value pair`** (gh 2.83.x + certain plugin combos). Fallback: `gh api -X PUT repos/<org>/<repo>/pulls/<pr>/merge -f merge_method=squash` performs the same merge via the raw REST endpoint and avoids whatever JSON-parse step is choking inside `gh pr merge`. Keep both forms in the local-drain script's merge step so an upstream gh-cli glitch doesn't stall the queue.

### 2026-05-14 (evening): Lekkertaal swarm — 4 lessons that apply to Ralph too

The planner-worker (`/ro:swarm`) ran 4 waves against `RonanCodes/lekkertaal`, 18 stories shipped. Four lessons from that run apply equally to Ralph's GitHub-source iteration when multiple stories close in the same session:

- **Workers must poll CI in foreground bash, NOT via an in-context monitor.** One worker exited with the line "I'll wait for the monitor events to come through" — a hallucinated tool flow that doesn't deliver events back into the worker context. The PR sat open with conflicts, no CI run, until the planner intervened. Fix: poll `gh api repos/<owner>/<repo>/commits/<sha>/check-runs` in a `bash` loop with `sleep 30` between attempts and a hard 15-minute cap. If checks stay pending past the cap, STOP and report; do not retry blindly.

- **Verify CI fired within 60s of `git push`.** Observed: a fresh branch push that did NOT trigger GitHub Actions. Force-pushing the same branch after a no-op rebase did trigger it. After every push, run `gh api .../actions/runs?head_sha=<sha>` once and check the count is > 0. If 0, nudge with `git commit --amend --no-edit && git push -f`. Root cause not isolated (possibly Actions transient or branch-protection quirk); the nudge reliably fixes it.

- **Rebase onto main when it drifts; do NOT merge main into the branch.** Wave 1's prompt-caching PR (#66) rebased cleanly onto wave 1's telemetry PR (#65) that had landed mid-flight, and ended up *composing* with it (cache token counts flowed into the new telemetry sink). Better outcome than landing in isolation. For Ralph: when push rejects because main moved, `git fetch origin && git rebase origin/main && git push -f --force-with-lease`. Never `git merge main`.

- **Trust local pre-push CI; skip waiting for GitHub Actions.** When the repo has a `.husky/pre-push` hook running the same gauntlet as GH CI (e.g. `pnpm test && pnpm build`), waiting for GH CI to re-run it costs 1-2 minutes per PR for zero added safety. New default: after `git push` succeeds (the hook validates), `gh api -X PUT .../pulls/<N>/merge -f merge_method=squash` immediately. GH CI still runs on the merged commit on main; if a fluke bug lands, post-merge CI flags it and the orchestrator can revert. Frequency of this in the lekkertaal 18-PR run: zero. Setup-time prompt asks the user once: "skip GH CI wait and merge immediately after a clean push? [Y/n]" — persisted in `.ralph/config.json` as `trust-local-ci: true|false`. Branch-protection rules with required-status-checks auto-override to `false`.

These lessons are now baked into the Pocock pattern page: [skill-lab:agent-native-repo-pocock](https://github.com/RonanCodes/llm-wiki-skill-lab-vault/blob/main/wiki/patterns/agent-native-repo-pocock.md) and the planner-worker SKILL: see `/ro:planner-worker` § "Lessons from live runs".

### 2026-05-19: Lekkertaal Phase 2 night shift — committed progress.txt was duplicate of git; subagents didn't backdate weekday commits

Run shape: PRD #127 (drill catalogue parity + spaced-rep loop closure), 10 stories, `--mode fresh --reviewer none`. All 10 PRs merged in ~2h. Follow-up e2e sweep added 8 specs across 3 batch PRs.

What worked:
- Auto-merge on green CI with no reviewer gate. Husky pre-push gauntlet caught everything CI would have. Zero post-merge regressions.
- Subagents (one per story) returned one-line summaries; orchestrator dispatched the next without ever touching the working tree mid-loop.
- Two follow-up issues that subagents naturally surfaced (#139, #140) — left open for review rather than auto-extending the loop.

What went wrong:
- **`.ralph/<phase>.progress.txt` was ~80% denormalised git history.** PR number, SHA, files changed — all already in `git log` + `gh pr diff`. The valuable bits (timestamps, learnings) were buried inside per-story entries where nobody read them after merge. And in a parallel worktree future this single file becomes a merge-conflict pinch point.
- **Phase 2 sweep subagents committed inside the 08:30–18:00 forbidden weekday window.** The Husky pre-push doesn't enforce the weekday-hours rule; the orchestrator's prompt to subagents didn't mention backdating; the subagents used real `git commit` and the commits landed at real wall-clock. Not catastrophic, but the rule exists for a reason.

What we changed in the skill (this version):
- **New artefact shape**: `patterns.md` (committed, durable, harvested at session close) + `<phase>.session.md` (committed, per-phase rolling aggregate) + `.ralph/sessions/<id>.md` (committed, per-session detail log written once after harvest) + `.ralph/sessions/<id>/<worker>.md` (gitignored worker scratch). Old `.ralph/<phase>.progress.txt` retired; legacy projects gitignore the path and let the historic file live in git history. See "Run artefacts (the canonical shape)" + "Worker scratch format" + "Codebase Patterns (the durable knowledge surface)" above.
  - **Revised 2026-05-19 evening**: the first cut of this shape (PR #7) over-corrected — it killed the per-iteration committed record entirely on the (correct) observation that the old `progress.txt` was ~80% redundant with git. But there IS value in a per-session committed record: crash recovery, cross-machine resume, and `cat .ralph/sessions/<id>.md` is much faster to read than `git log --since=... + gh pr view` for each PR. The fix: keep worker scratch gitignored (parallel-friendly) AND have the orchestrator write a single committed per-session detail log AT loop close, post-harvest. One file per session, orchestrator-only writer, no append-conflicts, captures the per-story prose + the non-promoted learnings. See "Run artefacts" table above (now four artefact classes, not three).
- **Orchestrator harvest step at loop close**: read worker scratch files, promote real learnings into `patterns.md`, finalise `<phase>.session.md`, commit both as one `chore(ralph): session N artefacts for <phase>`. Worker scratch dies (gitignored, disk-cheap, operator can read locally if needed).
- **First-run gitignore-policy prompt is retired.** Default rules are now fixed (`.ralph/sessions/`, `.ralph/*.progress.txt`, `.ralph/.gitignore-policy`). No more first-run friction.
- **Backdate rule for weekday commits is now an explicit subagent-prompt clause.** The orchestrator MUST include this in every implementer prompt:

  ```
  Weekday timestamp rule (CLAUDE.md): commits must fall outside 08:30–18:00 local time. Compute it once and pass via env:
    if it's currently inside that window AND it's Mon-Fri:
      pick a backdate (this morning's 07:55 if you started before 08:30; last night's 19:00 otherwise)
      export GIT_AUTHOR_DATE="<that ISO>"
      export GIT_COMMITTER_DATE="<that ISO>"
    else: skip the env, use real time.
  Use the same backdate for every commit in this iteration so they stay sequential.
  ```

- **Local factory naming**: this skill (plus planner-worker, matt-pocock-coding-workflow, day-shift, night-shift) is now called the **local factory** — collectively, the suite of agent-loop skills that run on Ronan's machine. The **remote factory** is the companion Factory app (tracked separately) that will run equivalent loops as a cloud service. Sibling skills should reference the local-factory family explicitly.

## PRD File Format (prd.json or phase-N-slug-YYYY-MM-DD.json)

```json
{
  "project": "llm-wiki",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2"
      ],
      "priority": 1,
      "status": "not-started",
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Story `status` values

| Value | Meaning | Implies `passes` |
|---|---|---|
| `not-started` | Hasn't been picked up yet | `false` |
| `in-progress` | Currently being worked on (only one story at a time per PRD) | `false` |
| `passed` | All DoD criteria met, PR merged, deploy verified | `true` |
| `deferred` | Skipped for this run because too big for one context window OR depends on a deferred story; the next Ralph run should pick it up | `false` |
| `needs-human` | Needs a manual dashboard step (OAuth registration, Nango webhook URL paste, etc.); Ralph can't complete without operator action. Mirrors the canonical `needs-human` lifecycle label on GH issues. | `false` |
| `blocked-on-code` | Needs a fix in another part of the codebase that's outside this PRD's scope; should become its own story in the next phase | `false` |

`passes: bool` is kept as a derived field for back-compat with older readers. `status` is canonical going forward.

When Ralph hits `deferred` or `blocked-*`, it MUST:
1. Write a `notes` line explaining the reason (one sentence).
2. Append the same line to the progress sidecar: `<ISO> US-NNN <STATUS> — <reason>`.
3. Continue to the next priority story; don't get stuck retrying.

## Story Size Rule

Each story must be completable in ONE iteration (one context window). If a story is too big, split it before running.

Right-sized: "Create vault-create skill with SKILL.md"
Too big: "Build the entire ingest system"
