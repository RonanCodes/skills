---
name: ralph
description: Run an autonomous Ralph loop to implement tasks from a PRD in .ralph/ OR from GitHub issues labelled `ready-for-agent` (agent-native repo pattern). Each iteration picks the highest-priority unfinished story, implements it in a fresh isolated context, opens ONE PR per story (squash-merged with `Closes #N` for GH source), validates, and updates progress. Supports named PRDs via --prd <name>, Kanban-style local files via --kanban, GitHub-issues source via --source github:<label>, and a reviewer-gate (Matt Pocock implementer/reviewer split) via --reviewer <model>. Modes: --mode fresh (default; one story = one fresh subagent), --mode batched (one context across stories, faster but riskier), --mode single (one story then stop). Use when you want to start the Ralph loop, run ralph, or implement PRD tasks autonomously.
category: development
argument-hint: [--prd <name>] [--source local|github:<label>] [--mode fresh|batched|single] [--kanban] [--reviewer <model>] [--plan-only] [--max-iterations <N>]
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# Ralph Loop

Autonomous coding agent loop based on the Ralph Wiggum technique. Each iteration picks one task from a PRD file under `.ralph/` OR from GitHub issues with a configured label (agent-native repo pattern; see `--source github:<label>`), implements it in a **fresh isolated context** by default, opens ONE PR per story, validates, commits, and updates progress.

## Source — auto-detect

The `--source` flag picks where stories come from:

- `--source local` (default when no gh remote, or when `.ralph/` already populated): reads from `.ralph/prd.json` (sequential) or `.ralph/issues/*.md` (with `--kanban`). Legacy behaviour.
- `--source github:<label>` (default when a gh remote is configured and `.ralph/` is empty): reads from open GitHub issues with the given label, e.g. `--source github:ready-for-agent` (or the project's synonym such as `Sandcastle`).

Auto-detect order: if `--source` is omitted, run `gh repo view --json url 2>/dev/null` and `ls .ralph/issues/ 2>/dev/null`. If a gh remote exists AND `.ralph/` is empty/absent → `--source github:ready-for-agent` is the default. If `.ralph/` is populated → `--source local` to honour existing work in flight. User can always override.

### GitHub-source iteration

When `--source github:<label>` is active, each iteration:

1. `gh issue list --label <label> --state open --json number,title,body,labels`
2. **Filter out `prd:draft` issues.** See "Filter / scope: prd:draft is NEVER picked up" below — this is a HARD GUARD.
3. Filter to **slice** issues (body opens with `## Parent\n\n#<N>`) — skip **parent PRD** issues (body opens with `## Problem Statement`). Parents are tracking issues, not work.
4. Filter to issues with no unsatisfied `Blocked by` (parse `## Blocked by` section, treat closed referenced issues as satisfied).
5. Pick the highest-priority unblocked slice (tie-break: lowest issue number).
6. Add label `in-progress` to the chosen issue (creates label if missing).
7. Implement in a fresh subagent context (same PR-per-story discipline as `local` mode).
8. Open the PR with `Closes #<slice-number>` in the body — GitHub auto-closes the slice on merge.
9. Remove `in-progress` label on PR open; the slice auto-closes on merge.
10. When the last slice for a parent PRD closes, comment "All slices merged" on the parent and close it.

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

**Shared Codebase Patterns:** if `.ralph/patterns.md` exists, treat it as global learnings read on every iteration regardless of which PRD is active. Individual progress files still carry the per-iteration detail.

## Gitignore Policy (first-run prompt)

Before the main loop runs, check `.ralph/.gitignore-policy`. If the file exists, read it and proceed. If missing, ask the user once using `AskUserQuestion`:

**Question:** "How should ralph's `.ralph/` folder be handled in git for this repo?"

**Options:**

1. **commit-all** (recommended) — Track PRDs, progress logs, patterns, and archive. PRs gain spec context, learnings are preserved, mid-phase handoffs work. Pick this unless you have a reason not to.
2. **commit-archive-only** — Commit `archive/`, `patterns.md`, and the policy file, but gitignore live `prd*.json` + `progress*.txt`. Middle ground — preserves finished-phase history without daily scratch.
3. **gitignore-all** — Fully gitignore `.ralph/`. Use for private experiments, rapid scratch PRDs, or data vaults where batch PRDs would be noise.

Write the chosen value (one of `commit-all`, `commit-archive-only`, `gitignore-all`) as a single line to `.ralph/.gitignore-policy`, then reconcile the repo's root `.gitignore`:

| Policy | `.gitignore` entries |
|--------|----------------------|
| `commit-all` | *(no entry — remove any existing `.ralph/` line)* |
| `commit-archive-only` | `.ralph/prd*.json`<br>`.ralph/progress*.txt` |
| `gitignore-all` | `.ralph/*`<br>`!.ralph/.gitignore-policy` |

In all three modes, `.ralph/.gitignore-policy` itself is tracked — so the team shares the policy decision. Under `gitignore-all` the pattern must be `.ralph/*` (not `.ralph/`) because git cannot negate files inside a fully-ignored directory.

Don't re-prompt once the file exists. To change policy later, edit `.ralph/.gitignore-policy` manually and update `.gitignore` to match.

## How It Works

0. Ensure `.ralph/.gitignore-policy` exists (see "Gitignore Policy" above); if not, prompt once and write it before touching any PRD
1. **Record session start** in `.ralph/<name>.session.md`: ISO timestamp, mode, max-iterations, reviewer, PRD path (see "Session timing" below)
2. Resolve PRD file from `--prd` flag (or default `.ralph/prd.json`) — find the highest priority story where `passes: false`
3. Read the matching progress file (and `.ralph/patterns.md` if present) — check Codebase Patterns section for learnings from prior iterations
4. **Record story start** timestamp in the orchestrator's notes (passed to the subagent prompt so it can echo it back in the progress entry)
5. **In `--mode fresh`: spawn a fresh subagent for this story.** In `--mode batched`: continue in current context. In `--mode single`: do this story then stop.
6. Implement the story against the EARS acceptance criteria
7. Validate (typecheck, lint, test — whatever the project requires; respect Definition of Done if present in the spec)
8. **Open ONE PR for this story** (no batching; see PR-per-story HARD GUARD above)
9. Commit with message: `<emoji> <type>(US-NNN): <Story Title>`
10. Wait for CI green; auto-merge via squash
11. **Record story finish** timestamp; compute duration; subagent embeds both into its progress.txt entry
12. Update the PRD file — set `status: "passed"`, `passes: true`, and `notes` including the squash SHA
13. Append progress to the matching progress file with timestamps + learnings
14. **On loop exit** (all stories complete OR max-iterations OR hard error): append the session-finish timestamp + total duration to `.ralph/<name>.session.md`

## One Story Per Iteration (in fresh / single modes)

In `--mode fresh` and `--mode single`, work on ONE story per iteration. After completing it:

- `single`: stop. Next `/ralph` invocation picks up the next story.
- `fresh`: spawn a NEW subagent for the next story (until `--max-iterations` or all stories pass).

In `--mode batched`, multiple stories share one context. This is the explicit opt-in for situations where the user accepts the risk in exchange for speed.

## Always fire Pushover at end (load-bearing default)

ANY `/ro:ralph` run against a real backlog ends with a `/ro:pushover` notification — done / paused / blocked / crashed. Confirmed 2026-05-14: autonomous coding runs always get a ping regardless of whether the user typed "AFK" or "night shift". The user can't tell from their phone if a run is still going or stopped 20 min in; a single end-of-run ping is the fix.

Skip Pushover ONLY when:

- `--plan-only` (nothing actually ran)
- `--mode single` and it's the only story (one-shot exploration, not a real run)
- User explicitly passed `--no-ping`

For the firing recipe (script path, env vars, message anatomy), see `~/Dev/ronan-skills/skills/pushover/SKILL.md`. Message shape: state + one concrete metric + what Ronan needs to do next. Example: `"ralph done — 14/14 stories merged, 0 deferred, ready for visual review"`.

## Progress Report Format

APPEND to the matching progress file (never replace). The progress file is `.ralph/<name>.progress.txt` when `--prd <name>` is used (e.g. `.ralph/phase-2-onboarding-2026-05-06.progress.txt`), otherwise `.ralph/progress.txt`. **Timestamps are mandatory** so the user can audit when each story actually ran (don't rely on git commit dates; those are often backdated for weekday-hours rules):

```
## [Story ID]: [Story Title]
- started: 2026-05-11T23:35:12+02:00
- finished: 2026-05-11T23:44:41+02:00
- duration: 9m29s
- PR: #61 (squash-merged 8240af6)
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context for next tasks
---
```

Both `started` and `finished` are real wall-clock ISO 8601 timestamps with offset, NOT the backdated git commit dates. The subagent records `started` first thing after reading its prompt (capture via `date -u +%Y-%m-%dT%H:%M:%S%z` or the local-tz equivalent), and `finished` right before it returns its one-line summary. `duration` is computed in the implementer subagent and embedded; the orchestrator does not need to compute or merge times.

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

Compute the per-story aggregates by summing each story's `duration` field in the progress.txt; the orchestrator does that at loop-exit time.

Total wall-clock and orchestrator-overhead can both be derived: total = `finished - started` from the session line, subagent-sum from the per-story durations, orchestrator-overhead = total minus subagent-sum.

The session log is committed alongside the PRD + progress under the same `commit-all` gitignore policy.

## Codebase Patterns

Reusable, cross-PRD patterns live in `.ralph/patterns.md` (shared across all named PRDs). Read it on every iteration. Add to it only when you discover a pattern general enough to benefit future stories in any PRD:

```
## Codebase Patterns
- Skills use SKILL.md format with YAML frontmatter
- Vault CLAUDE.md files are thin config, not logic
- Use wikilinks [[page]] syntax for cross-references
```

PRD-specific learnings (gotchas tied to one story, one-off fixes) stay in the per-PRD progress file, not in `patterns.md`.

If `.ralph/patterns.md` does not exist, create it on first use. Legacy projects that only use `.ralph/progress.txt` may continue to keep a `## Codebase Patterns` section at the top of that file — both conventions are supported.

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
| `blocked-on-human` | Needs a manual dashboard step (OAuth registration, Nango webhook URL paste, etc.); Ralph can't complete without operator action | `false` |
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
