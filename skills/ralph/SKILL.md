---
name: ralph
description: Run an autonomous Ralph loop to implement tasks from a PRD in .ralph/. Each iteration picks the highest-priority unfinished story, implements it in a fresh isolated context, opens ONE PR per story (squash-merged), validates, and updates progress. Supports named PRDs (e.g. one per project phase) via --prd <name>. Modes: --mode fresh (default; one story = one fresh subagent), --mode batched (one context across stories, faster but riskier), --mode single (one story then stop). Use when you want to start the Ralph loop, run ralph, or implement PRD tasks autonomously.
category: development
argument-hint: [--prd <name>] [--mode fresh|batched|single] [--plan-only] [--max-iterations <N>]
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# Ralph Loop

Autonomous coding agent loop based on the Ralph Wiggum technique. Each iteration picks one task from a PRD file under `.ralph/`, implements it in a **fresh isolated context** by default, opens ONE PR per story, validates, commits, and updates progress.

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

## Per-story fresh context (recommended)

When `--mode fresh` is selected, each iteration MUST:

1. Read `.ralph/prd.json` to find the next unfinished story
2. Read `.ralph/patterns.md` if it exists (carries cross-iteration learnings)
3. **Spawn a NEW subagent via the Agent tool** with `subagent_type: general-purpose` (or a more specialised type if appropriate)
4. The subagent's prompt is self-contained: includes the story's full EARS criteria, design ref, Definition of Done, and a copy of `.ralph/patterns.md`
5. The subagent does the work end-to-end: implement, test, commit, push, open PR, watch CI green, squash-merge, mark `passes: true`, append to `progress.txt`
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
1. Resolve PRD file from `--prd` flag (or default `.ralph/prd.json`) — find the highest priority story where `passes: false`
2. Read the matching progress file (and `.ralph/patterns.md` if present) — check Codebase Patterns section for learnings from prior iterations
3. **In `--mode fresh`: spawn a fresh subagent for this story.** In `--mode batched`: continue in current context. In `--mode single`: do this story then stop.
4. Implement the story against the EARS acceptance criteria
5. Validate (typecheck, lint, test — whatever the project requires; respect Definition of Done if present in the spec)
6. **Open ONE PR for this story** (no batching; see PR-per-story HARD GUARD above)
7. Commit with message: `<emoji> <type>(US-NNN): <Story Title>`
8. Wait for CI green; auto-merge via squash
9. Update the PRD file — set `passes: true` for completed story
10. Append progress to the matching progress file with learnings

## One Story Per Iteration (in fresh / single modes)

In `--mode fresh` and `--mode single`, work on ONE story per iteration. After completing it:

- `single`: stop. Next `/ralph` invocation picks up the next story.
- `fresh`: spawn a NEW subagent for the next story (until `--max-iterations` or all stories pass).

In `--mode batched`, multiple stories share one context. This is the explicit opt-in for situations where the user accepts the risk in exchange for speed.

## Progress Report Format

APPEND to the matching progress file (never replace). The progress file is `.ralph/<name>.progress.txt` when `--prd <name>` is used (e.g. `.ralph/phase-2-onboarding-2026-05-06.progress.txt`), otherwise `.ralph/progress.txt`:

```
## [Date/Time] - [Story ID]: [Story Title]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context for next tasks
---
```

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
