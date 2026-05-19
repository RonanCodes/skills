---
name: planner-worker
description: Multi-agent coding swarm. Planner / worker / merger over git worktrees on the Max plan. Reads a grilled PRD from `.ralph/<name>/prd.md` OR a pre-ranked queue from `/ro:night-shift`, dispatches parallel Claude Code Agent workers (one per vertical-slice issue in its own git worktree) with hybrid file-area conflict detection, and a merger Agent reviews + merges clean work back to the target branch. Defers to /ro:repo-mode for `--github` default — `personal` repos open PRs and create issues; `work` repos run fully local with no GH side-effects so the swarm stays invisible to the work GH/Jira/ADO project. Alias `/ro:swarm`. Use when you want to kick off the swarm, run a planner+worker swarm, parallel-implement a backlog, run an AFK night-shift coding session, or scale a PRD beyond what a single Ralph loop can chew through. For multi-wave indefinite drain + refill, use `/ro:night-shift` (which wraps this).
category: development
argument-hint: [--prd <name>] [--queue <path>] [--workers <N>] [--github] [--judge-agent] [--afk] [--auto-approve] [--skip-grill] [--staging-branch <name>] [--resume] [--max-cycles <N>] [--max-runtime <duration>] [--unsafe-many] [--no-scout]
allowed-tools: Bash Read Write Edit Glob Grep Agent AskUserQuestion
---

# /ro:planner-worker (alias /ro:swarm)

Multi-agent coding swarm. Sibling to `/ro:ralph`. Where Ralph is one agent doing stories in series, planner-worker is N agents doing stories in parallel under a planner and a merger, with optional judge-agent termination.

## When to use

- A PRD has been grilled via `/ro:grill-me` and written via `/ro:write-a-prd` and now has 5+ vertical-slice issues to ship
- You want overnight autonomous execution (`--afk`)
- The issues are independent enough that parallelisation actually helps (the planner emits `depends_on` to serialise hot-file work)
- You're on the Max plan and want Agent-tool fan-out, not API-billed Sandcastle

## When NOT to use

- One-shot single-story task (use `/ro:ralph --mode single`)
- Cross-repo / monorepo coordination (out of scope v1)
- Hostile-code or untrusted-input runs (no container isolation; future `--sandcastle` flag)
- You don't have a PRD yet (run `/ro:grill-me` then `/ro:write-a-prd` first)

## Quick start

```
# Interactive: grills you for config, then runs against a named PRD
/ro:planner-worker --prd lekkertaal-pwa-bootstrap

# Autonomous night-shift (AFK)
/ro:planner-worker --prd lekkertaal-pwa-bootstrap --afk

# Real GitHub issues + PRs
/ro:planner-worker --prd lekkertaal-pwa-bootstrap --github

# Resume after a human-resolved escalation
/ro:planner-worker --resume
```

## Filter / scope: `prd:draft` is NEVER picked up

**`prd:draft` issues are NEVER picked up by this skill.** They represent ideas captured in the agent-native repo's "inbox", not ready work. Drafts have freeform bodies, NOT Pocock's 7-section template, and have not been grilled. The planner picking one up would mean dispatching workers against an unfinished spec.

To promote a draft into ready work, the user runs `/grill` on the issue. The `grill-with-docs` flow rewrites the body into the Pocock 7-section template, then the user swaps the label from `prd:draft` to the repo's gate label (`ready-for-agent` by default, or the project synonym like `Sandcastle` / `swarm` configured in `docs/agents/triage-labels.md`).

When the planner (or any phase of this skill) queries GitHub for backlog issues — typically via `--source github:<label>` from `/agentic-e2e-flow` or `/ro:night-shift` — ALWAYS exclude `prd:draft`. `gh` label semantics are tricky: `--label <gate>` matches issues that have the gate label, but an issue can have BOTH `prd:draft` AND the gate label (mis-labelling drift). Defence in depth:

1. Pass `--label <gate>` to scope the initial query.
2. Post-filter the JSON: drop any issue whose `labels[].name` contains `prd:draft`.
3. Equivalently, use `gh issue list --label <gate> --search "-label:prd:draft" ...` to push the exclusion server-side.

**Tip:** if you're not sure what's queued vs what's still an idea, run `/ro:list-draft-prds` first to see the drafts inbox before kicking off the swarm.

## US-0: Interactive config grilling

Unless `--skip-grill` (or `--afk` which implies it) is passed, the skill opens with a project-aware grilling phase. Each missing flag is asked via `AskUserQuestion`, one at a time, with a recommendation derived from project state.

Order and project-awareness rules:

1. **GitHub issues + PRs for this run?**
   - Resolve repo mode first via the 4-line snippet from `/ro:repo-mode`. If `mode == work` → recommend "no" (hard rule, do NOT prompt; work-mode repos must stay invisible to the work GH/Jira/ADO project). If `mode == personal` → recommend "yes" when a gh remote resolves. If `mode == unset` → run the first-run prompt from `/ro:repo-mode` § "First-run prompt", persist, then re-resolve.
   - Probe: `gh repo view --json visibility,nameWithOwner 2>/dev/null`
   - For `personal` mode: recommend "yes" when a remote resolves and visibility is `PRIVATE`; "no" when no remote configured or repo is public + you don't want noise.
   - CLI equivalent: `--github`

2. **Worker count?**
   - Probe: cores via `sysctl -n hw.ncpu` (macOS) or `nproc` (linux); free disk on `.swarm/worktrees/` parent via `df -k .`
   - Recommend `min(3, floor(cores/2))` and warn if free disk < `(repo_size_mb * worker_count * 2)`
   - CLI equivalent: `--workers N`

3. **Run mode?**
   - Recommend "interactive" by default
   - Offer "AFK" if the user said anything like "kick off and ping me", "run overnight", "wake me when done"
   - CLI equivalent: `--afk` for AFK, nothing for interactive

4. **Merge target?**
   - Probe: `git rev-parse --abbrev-ref HEAD`
   - Recommend the current branch; offer a staging branch (`swarm-staging`) as alt
   - CLI equivalent: `--staging-branch <name>` to override; default = current branch

5. **Worker model?**
   - Recommend `sonnet`; offer `opus` only if the PRD is flagged as "research-heavy" (more than 3 issues mention "investigate" or "explore")
   - CLI equivalent: encoded in `.swarm.json` `models.worker`

6. **Add a Judge agent?**
   - Heuristic: count concrete acceptance criteria in the PRD. If the PRD looks "closed" (>= 3 numbered acceptance criteria), recommend "no". If open-ended ("we'll know when we see it"), recommend "yes"
   - CLI equivalent: `--judge-agent`

7. **Trust local pre-push CI; skip waiting for GitHub Actions?**
   - Probe: `test -f .husky/pre-push` AND grep that file for any of `pnpm quality`, `pnpm test`, `pnpm build`, `pnpm lint`, `pnpm typecheck`
   - Recommend "yes" when a pre-push hook with at least build + test + lint is present (the case in any repo scaffolded by `/ro:new-tanstack-app`)
   - Recommend "no" when no pre-push hook, OR when the repo's `.github/workflows/*.yml` runs checks that are NOT in the pre-push hook (e.g. cross-OS matrix, integration tests against a managed service)
   - CLI equivalent: `--trust-local-ci` (yes) or `--wait-for-gh-ci` (no)
   - Persisted in `.swarm.json` as `trust-local-ci: true|false`
   - Workers configured with `trust-local-ci=true` push, verify the push hook ran clean, and squash-merge immediately. They do NOT poll `gh api .../check-runs`.
   - If the repo has branch-protection rules that require status checks, the planner detects this via `gh api repos/<owner>/<repo>/branches/main/protection` and overrides to `wait-for-gh-ci=true` (printing why)

Each answer is echoed back as the CLI flag the user could have passed next time, e.g. "noted, equivalent to `--workers 5`". CLI flags supplied at invocation skip their corresponding prompt.

`--skip-grill` short-circuits to defaults: `workers=3`, `github=<true if repo-mode=personal AND gh remote present, else false>`, `mode=interactive`, `merge-target=current-branch`, `worker-model=sonnet`, `judge-agent=false`, `trust-local-ci=true`. The `github` default specifically defers to `/ro:repo-mode` — work-mode repos always run with `github=false` so nothing leaks to the work GH/Jira/ADO project. If repo-mode is `unset` and `--skip-grill` is in play (e.g. `--afk`), default `github=false` (safe failure mode); a separate session will catch the unset state and prompt.

## US-1: Planner

The planner is invoked once at the start of a run via the **Agent tool**, with the **Opus** model.

Planner prompt template (see `scripts/planner-prompt.sh` for the canonical version):

```
You are the PLANNER agent for /ro:planner-worker.

Read the PRD at .ralph/<name>/prd.md.
Explore the codebase enough to size the work.
Emit a backlog of vertical-slice issues to .ralph/<name>/issues/<NNN>-<slug>.md.

Each issue file MUST have frontmatter:

  id: 001
  title: <one-line>
  status: ready
  depends_on: []        # array of issue ids that must merge first
  estimate: <S|M|L>
  dod:
    - <pnpm test passes>
    - <pnpm typecheck passes>
    - <any extra acceptance check>

Body: 5-30 lines describing what to build + why, file pointers, test plan.

Rules:
- Vertical slices only. No "scaffold the schema" issues without a UI touchpoint.
- Mark depends_on for hot-file conflicts (two issues touching the same component).
- 3-12 issues for v1. If you'd plan more than 12, split the PRD instead.
- Exit cleanly when issues are written. Do not implement anything.
```

The planner is **only** re-invoked under US-7 (worker failure re-decomposition).

## US-2: Confirm the backlog

After the planner exits, the skill prints a one-screen summary:

```
Backlog plan ready (.ralph/<name>/issues/):

  001 [S] schema: add points column                    deps: -
  002 [M] service: award points on completed task      deps: 001
  003 [M] dashboard: tile rendering points trend       deps: 002
  004 [S] hook: usePoints                              deps: 001
  005 [M] integration test: points e2e                 deps: 003,004

Dispatch order: [001] -> [002, 004] -> [003] -> [005]
Workers will run up to N=3 in parallel.

[y] dispatch  [n] re-plan with feedback  [q] abort
```

Skipped under `--auto-approve` or `--afk`. Rejecting with feedback re-invokes the planner Agent with the feedback inlined.

## US-2b: Ranked queue input from /ro:night-shift

When invoked with `--queue <path>`, the skill skips US-1 (planner runs) and US-2 (confirmation) and reads the ranked slice list straight from the file. Format is a one-slice-per-line plaintext list of `<issue-number>` (when `--github`) or `<issue-id>` (when local). Used by `/ro:night-shift` to pass its ranker output through and prevent every wave from re-running the planner Agent.

The file is consumed in order — top of file = highest priority. The skill still respects `depends_on` and the US-3b file-area graph; the ranked order only sets dispatch priority among work that's otherwise dispatchable.

`--queue` and `--prd` are mutually exclusive. When `--queue` is set the planner Agent is NOT re-invoked; that's the night-shift loop's job between waves.

## US-3: Worker dispatch

For each unblocked issue (`depends_on` all `merged` or empty), up to the worker cap:

1. `git worktree add .swarm/worktrees/<id> -b swarm/<id>` from the merge-target branch
2. Append `.swarm/` to `.gitignore` if not already present (commit only on first run, on a `chore(swarm): gitignore .swarm` commit)
3. Spawn a Claude Code Agent (default Sonnet) with the issue body as instructions and working directory pinned to the new worktree

Workers are dispatched as **multiple Agent tool calls in a single assistant message** so the runtime fans out. They are independent and do not coordinate.

### US-3b: File-area conflict detection (hybrid static + scout)

Two parallel workers touching the same files race each other at merge time. The skill mitigates this with a hybrid graph, separate from the `depends_on` graph:

**Static pass (every wave, free):** read each candidate slice body for:

- A `## Files touched` or `## Touches` section listing paths
- An `estimate:` or `paths:` frontmatter array
- Inline mentions matching `src/...`, `app/...`, `apps/...`, `packages/...`, `drizzle/...`, etc.

Two slices conflict if their declared path sets intersect by exact file OR share a directory at depth ≥ 2 (e.g. `src/routes/settings.tsx` and `src/routes/settings.test.ts` collide via `src/routes/`). Conflicting slices are **never dispatched in the same wave**, even if they're both unblocked.

**Scout pass (only after a wave hits a cross-worker merge conflict):** spawn a one-shot scout sub-agent per remaining candidate slice with the prompt:

```
You are a SCOUT sub-agent for /ro:planner-worker.

Slice: <issue body inlined>

Task: read the slice and predict the SET of file paths the implementation will touch.
Output a JSON object on stdout, nothing else:
  {"paths": ["src/routes/...", "src/lib/..."], "confidence": "high|medium|low"}

Rules:
- Do not edit anything.
- Do not run pnpm install or any side-effects.
- Read the codebase enough to be accurate. ~2-3 min budget.
- If you cannot tell, output paths: [] with confidence: low.
```

Scout outputs are merged into the file-area graph and persist for subsequent waves of the same run.

`--no-scout` disables the scout pass entirely (purely static). Use when you'd rather waste worker time on conflicts than spend planner time on probing.


Worker prompt template (see `scripts/worker-prompt.sh`):

```
You are a WORKER agent for /ro:planner-worker.

Issue: .ralph/<name>/issues/<id>-<slug>.md (full body inlined here)
Worktree: .swarm/worktrees/<id>/
You are pinned to this worktree. Do NOT touch sibling worktrees.

Workflow:
1. Read the issue body
2. Implement the feature/fix
3. Run the DoD commands (auto-detected or .swarm.json `dod`)
4. Only exit successfully when ALL DoD commands pass
5. Commit on the worktree branch with an emoji-conventional message
6. Append a one-line summary to .swarm/logs/<id>.log

Rules:
- One commit per logical change, but ALL must land before exit
- Do not push (the merger handles that)
- Do not edit issues/, prd.md, or other worktrees
- If you fail DoD after one retry with the failure context, exit with status "stuck" and a one-line cause to .swarm/logs/<id>.log
```

## US-4: DoD detection + override

Auto-detect from `package.json` in this order:

1. `.swarm.json` `dod` block (highest precedence)
2. If `package.json` has `scripts.test` and `scripts.typecheck`: use them
3. Else if `tsconfig.json` present: `tsc --noEmit`
4. Else: `pnpm test` if `pnpm-lock.yaml` present; `npm test` if `package-lock.json` present

If `.swarm.json` lists `dod.extras`, append those (e.g. `pnpm lint`, `./verify-quick.sh`).

Worker exits successfully **only** when every DoD command passes (non-zero exit = stuck).

## US-5: Merger agent

When a worker reports green, dispatch a **merger Agent** (Opus) for that worktree:

```
You are the MERGER agent for /ro:planner-worker, issue <id>.

Worktree: .swarm/worktrees/<id>/
Merge target: <merge-target-branch>

Workflow:
1. cd into the worktree
2. Read the diff (git diff <merge-target>...HEAD)
3. Sanity check vs the issue spec: does the diff match the DoD? Any obvious red flags?
4. git rebase <merge-target>
5. Re-run the DoD commands on the rebased branch
6. If clean: cd back to repo root and `git merge --no-ff swarm/<id>` (or `gh pr merge --squash` if --github)
7. On success: `git worktree remove .swarm/worktrees/<id>` and `git branch -D swarm/<id>`
8. On any failure (rebase conflict, DoD red, or red flags in the diff): STOP, write one-line cause to .swarm/status.md, exit "escalated"
```

The merger has merge authority on the merge-target branch. Default = the branch the skill was invoked from. `--staging-branch swarm-staging` routes merges to a staging branch instead; main is updated only when the user explicitly merges staging.

## US-6: Escalation

If the merger exits `escalated`:

1. Leave the worktree intact (forensics)
2. Append a one-line summary to stdout AND `.swarm/status.md` (under `Escalations:`)
3. Mark the issue `status: escalated` in its file
4. The dispatcher continues with the next unblocked issue
5. On all-issues-resolved-or-escalated, the run pauses for the user
6. User fixes the conflict, then `/ro:planner-worker --resume` picks up where we left off

## US-7: Worker failure -> planner re-plan

If a worker exits stuck:

1. Mark the issue `status: stuck`
2. Retry ONCE with the failure context inlined in the worker prompt (single retry, not a loop)
3. If retry still stuck: re-invoke the **planner Agent** with:
   - The stuck issue body
   - The worker's failure log
   - Instructions to decompose this single issue into 2-4 smaller sub-issues that route around the failure mode
4. New sub-issues are appended to `.ralph/<name>/issues/` with ids like `001a`, `001b` and `depends_on` set sensibly
5. Original stuck issue is marked `status: replaced-by: [001a, 001b]`
6. Dispatcher picks up the new sub-issues next cycle

This is the **only** path that re-invokes the planner mid-run.

## US-8: --github flag

When `--github` is set:

- The planner ALSO calls `gh issue create --title <title> --body <body> --label swarm` for each backlog issue and stores the issue number in the issue file's frontmatter (`github-issue: 42`)
- Workers `git push origin swarm/<id>` and `gh pr create --base <merge-target> --head swarm/<id> --title <title> --body "Closes #42"`
- Merger uses `gh pr merge --squash --delete-branch` instead of local merge
- On escalation, the PR is left open with a `swarm:escalated` label added
- Prereq: `gh auth status` must be green; `gh repo view` must resolve; the skill fails loudly otherwise

## US-9: --judge-agent

Default termination: empty backlog = exit.

With `--judge-agent`, after each dispatch cycle (one cycle = "dispatch all unblocked, wait for all merged or escalated"), invoke a **judge Agent** (Opus):

```
You are the JUDGE agent for /ro:planner-worker.

PRD: .ralph/<name>/prd.md (re-read it)
Backlog state: .ralph/<name>/issues/ (re-read all)
This cycle: <summary of merged + escalated>

Decide: KEEP_GOING or STOP.

KEEP_GOING means: the PRD has goals not yet covered by the merged backlog, and you can describe what's missing in 1-3 bullets. Returning KEEP_GOING re-invokes the planner with those bullets.

STOP means: the PRD's acceptance criteria are met, or all remaining work is escalated, or you're going in circles.

Hard caps (regardless of judge): --max-cycles (default 10), --max-runtime (default 4h).
```

KEEP_GOING re-invokes the planner with the judge's missing-work bullets; STOP exits cleanly.

## US-10: --afk

`--afk` is the autonomous combination flag. It implies:

- `--auto-approve` (skip US-2 confirmation)
- `--judge-agent` (Cursor-style termination)
- `--skip-grill` (use defaults for unspecified flags)

## Always fire completion-report + Pushover at end (load-bearing default)

ANY `/ro:planner-worker` run against a real backlog ends with TWO tail calls, in this order:

1. **`/ro:completion-report --prs <merged-pr-list> --title "<prd-name> swarm" --no-open`** — writes a browsable HTML report to `<repo>/.completion-reports/<ts>-<slug>.html` with per-PR cards (CI status, file stats, summary), per-file diffs, per-PR revert command, per-file rollback command, and a risk panel (schema migrations, env changes, large deletions, lockfile-only PRs, no-tests-on-feat). Capture the absolute path it prints. Pass `--prs` rather than `--prd` because the swarm tracks the merged PR list directly; falls back to `--prd <name>` if PR list isn't available.
2. **`/ro:pushover --url file://<path-from-step-1>`** — sends the done / paused / blocked / crashed ping with the report path as a deep link.

If step 1 reports an empty range, skip `--url` on step 2 but STILL send the ping with state.

Pushover message anatomy:

```
night shift done: <N> stories merged, <M> stuck, <duration>
```

with the report URL attached so tapping the notification opens the diff browser.

Skip BOTH tail calls ONLY when:

- `--plan-only` (planner runs but no workers dispatch)
- User explicitly passed `--no-ping`

Per the global Pushover firing rule (see `~/CLAUDE.md` § Pushover Notifications, condition 4) and the completion-report skill at `~/Dev/ronan-skills/skills/completion-report/SKILL.md`.

## US-11: --workers N

`N` defaults to 3. Hard ceiling of 10 without `--unsafe-many`. Above 10:

```
WARNING: >10 worktrees will likely thermal-throttle your laptop and consume
<estimate_mb> MB of disk via duplicate node_modules. Pass --unsafe-many to
override.
```

The skill computes `estimate_mb` as `repo_size_mb * worker_count`.

## US-12: --resume

After a human-resolved escalation, `--resume`:

1. Re-reads `.swarm/status.md` and `.ralph/<name>/issues/*.md`
2. Re-dispatches any issue with `status: ready` and unmet `depends_on` now met
3. Re-attempts any issue with `status: escalated` whose worktree was modified since the escalation timestamp
4. Idempotent: running `--resume` on a clean state is a no-op

## US-13: Live status + logs

During the run:

- `.swarm/logs/<id>.log` is the worker's own append-only log
- `.swarm/status.md` is rewritten on every state change with this template:

```markdown
# planner-worker live status

PRD: <name>
Started: <ISO8601>
Cycle: <N> of <max>

## Workers active
- 002 (worker, 4 min)
- 003 (merger, rebasing)

## Merged
- 001 schema: add points column          <commit-hash>

## Escalated
- (none)

## Stuck (retrying)
- (none)

## Last 5 events
- 12:14:02 worker-001 GREEN
- 12:14:05 merger-001 dispatched
- 12:14:18 merger-001 MERGED  abc1234
- 12:14:19 worker-002 dispatched
- 12:14:19 worker-003 dispatched
```

Tail with `watch -n 2 cat .swarm/status.md` or `code -r .swarm/status.md`.

## US-14: Postmortem on exit

On final exit, the skill writes `.swarm/run-<ISO8601>.md`:

```markdown
# Swarm run postmortem

PRD: <name>
Duration: 47m 12s (started 2026-05-14T07:30Z, ended 2026-05-14T08:17Z)
Workers cap: 3

## Planned issues: 5
- 001 schema: add points column
- 002 service: award points on completed task
- 003 dashboard: tile
- 004 hook: usePoints
- 005 integration test

## Merged: 4
- 001  abc1234  (4 min worker, 2 min merger)
- 002  def5678  (8 min worker, 1 min merger)
- 003  ghi9abc  (12 min worker, 3 min merger)
- 004  jkl0def  (6 min worker, 1 min merger)

## Stuck: 1
- 005 integration test: failed e2e setup after retry; planner re-decomposed into 005a, 005b (queued for next run)

## Escalated: 0

## PRs (github mode)
- (n/a; local merge mode)
```

## Per-repo config (.swarm.json)

Optional. If present in the repo root:

```json
{
  "dod": {
    "test": "pnpm test",
    "typecheck": "pnpm typecheck",
    "extras": ["pnpm lint", "./verify-quick.sh"]
  },
  "models": {
    "planner": "opus",
    "worker": "sonnet",
    "merger": "opus",
    "judge": "opus"
  },
  "workers": 3,
  "github": false,
  "merge-target": "main"
}
```

Sensible defaults when the file is absent. CLI flags always win over the file.

## File layout (in the user's repo)

```
.ralph/<name>/
  prd.md
  issues/
    001-schema-points.md
    002-service-award.md
    ...

.swarm/                         # gitignored
  swarm.json                    # optional config
  worktrees/                    # active git worktrees
    001-schema-points/
    ...
  logs/
    001-schema-points.log
    ...
  status.md                     # live state
  run-<ISO8601>.md              # postmortem (one per run)
```

## Anti-patterns

- DO NOT silently flip to batched / no-worktree mode. Worktree isolation is the whole point
- DO NOT run without a PRD. If `.ralph/<name>/prd.md` is missing, fail loudly and point to `/ro:write-a-prd`
- DO NOT mutate `main` directly from the worker; only the merger has merge authority
- DO NOT push worker branches in non-`--github` mode (no noise on origin)
- DO NOT exceed 10 workers without `--unsafe-many`. Real laptops thermal-throttle hard

## Lessons from live runs

Captured from the lekkertaal swarm run on 2026-05-14 (8 PRs landed across two waves). These are baked into the prompt template each worker receives.

### 1. Pre-assign migration numbers when N workers all touch the DB

When multiple workers each run `pnpm drizzle-kit generate`, they all grab the same next number (e.g. `0004`) and stomp `drizzle/meta/_journal.json`. The conflict is mechanical to resolve but burns planner cycles.

**Fix:** the planner assigns each DB-touching worker a unique migration slot in its dispatch prompt: *"your migration is `0007_<slug>.sql`; do not run `drizzle-kit generate` until you've manually claimed that number in `_journal.json`."* Workers without a DB change don't get a slot.

### 2. Worker poll loops must be foreground bash, NOT in-context monitor

Workers that delegate CI watching to an in-context monitor tool can park silently if the monitor doesn't deliver events back into the worker's conversation. We saw one worker exit with "I'll wait for the monitor events to come through" — the PR was open, conflicts present, and the worker never came back.

**Fix:** the dispatch prompt MUST tell the worker to poll CI via a foreground `bash` loop using `gh api repos/<owner>/<repo>/commits/<sha>/check-runs`, sleep 30s, re-poll. Hard cap 15 minutes. NEVER use an in-context monitor for this. If checks stay pending past the cap, STOP and report; do not retry blindly.

### 3. CI may not trigger on the first push to a new branch

We observed a worker push a branch + open a PR, and GitHub Actions did not fire on it. Force-pushing the same branch after a no-op rebase triggered CI normally. Root cause not fully isolated — could be path-filter quirk, draft-PR gating, or a brief Actions hiccup.

**Fix:** after `git push`, the worker must verify CI fired within 60s via `gh api .../actions/runs?head_sha=<sha>`. If no run exists, force-push a no-op (`git commit --amend --no-edit && git push -f`) to nudge it. If that still doesn't work, escalate to the planner.

### 4. Workers should rebase, not merge, on parent-branch drift

When PR-1 lands while PR-2 is still in flight, PR-2 will hit conflicts. Rebasing PR-2 onto the new main and force-pushing is cleaner than merging main into PR-2 (which leaves merge bubbles in the PR). The lekkertaal run #66 (prompt caching) rebased cleanly onto #65 (telemetry) mid-flow and ended up composing both behaviours — a real win.

**Fix:** worker prompt should say *"if your push is rejected because main moved, rebase onto origin/main, resolve conflicts, force-push-with-lease. Do not merge main into your branch."*

### 5a. Parallel workers MUST use isolated worktrees; verify on arrival

Even with `isolation: "worktree"` in the Agent tool, workers occasionally land on the SHARED main checkout instead of a fresh worktree. When that happens, parallel workers stomp each other's uncommitted edits as they `git checkout` between branches. Observed 4+ times in the lekkertaal run (PRs #79, #82, #100, #103).

**Symptoms:** a worker reports "the main checkout had uncommitted edits from another worker" or "my edits were wiped when another worker switched branches".

**Fix in worker prompt:** every dispatch prompt should include a self-check at the top:

```
ON ARRIVAL:
1. Run `git worktree list` and `pwd`. Confirm your pwd is NOT
   <main-repo-path>. If it IS, create your own worktree at
   `<main-repo-path>-wt-<issue-number>` and `cd` into it.
2. `git status` should show clean (no other worker's edits).
3. Only then start work.
```

This guarantees isolation even when the harness's `isolation: "worktree"` doesn't take effect for some reason. The cost is one extra mkdir + checkout per worker; the benefit is no lost work.

**Fix in planner:** when 3+ workers are dispatched in parallel and ANY two report worktree collisions, the planner should add a pre-dispatch step that creates the worktrees explicitly and passes the path to each worker.

### 5. Trust local pre-push CI; do not wait for GitHub Actions

If the repo has a husky `pre-push` hook running `pnpm quality-checks` (format + lint + build + test + audit), pushing a branch already proves the same checks GitHub Actions will run. Waiting for GH CI to repeat the gauntlet adds 1-2 minutes per worker for zero additional safety.

**Default (`--trust-local-ci`, ON):** workers run local checks, push, immediately squash-merge. If pre-push hook is missing or `SKIP_QUALITY_CHECKS=1` was used, fail loudly and do not merge.

**Opt-out (`--wait-for-gh-ci`):** workers still poll `gh api .../check-runs` and only merge on green. Use when:
- The repo has no pre-push hook
- The repo lacks parity between local and CI (e.g. CI does additional integration tests against managed services)
- The repo has branch-protection rules that require status checks before merge (in which case the planner cannot merge without CI green anyway — the flag is forced ON)

**Setup-time prompt (US-0):** the planner asks the user once per repo:

> "This repo has a pre-push hook running [<list of checks>]. GitHub Actions runs effectively the same checks. Skip GH CI wait and merge immediately after a clean push? [Y/n]"

The answer is persisted in `.swarm.json` as `trust-local-ci: true|false`.

**Safety net:** GH CI still runs on the merged commit on main. If a fluke bug lands, the post-merge CI run will flag it on main, and the planner can revert. The frequency of this happening (zero in the lekkertaal 8-PR run) does not justify the per-PR wait cost.

## See also

- `/ro:ralph` — single-agent serial sibling
- `/ro:grill-me` — upstream PRD grilling
- `/ro:write-a-prd` — PRD writer that emits `.ralph/<name>/prd.md`
- `/ro:pushover` — notification fired at end of `--afk` runs
- `/ro:drain-pr-queue` — clean up old swarm-opened PRs after the run
- `/ro:swarm` — friendly alias for this skill
- `/ro:night-shift` — wraps this skill in a multi-wave drain + refill loop with explicit-scope opening grill. Use when you want indefinite overnight runs across the whole backlog, not just one PRD
- `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md` — skill-lab page with provenance
