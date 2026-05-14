---
name: planner-worker
description: Multi-agent coding swarm. Planner / worker / merger over git worktrees on the Max plan. Reads a grilled PRD from `.ralph/<name>/prd.md`, dispatches parallel Claude Code Agent workers (one per vertical-slice issue in its own git worktree), and a merger Agent reviews + merges clean work back to the target branch. Alias `/ro:swarm`. Use when you want to kick off the swarm, run a planner+worker swarm, parallel-implement a backlog, run an AFK night-shift coding session, or scale a PRD beyond what a single Ralph loop can chew through.
category: development
argument-hint: [--prd <name>] [--workers <N>] [--github] [--judge-agent] [--afk] [--auto-approve] [--skip-grill] [--staging-branch <name>] [--resume] [--max-cycles <N>] [--max-runtime <duration>] [--unsafe-many]
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

## US-0: Interactive config grilling

Unless `--skip-grill` (or `--afk` which implies it) is passed, the skill opens with a project-aware grilling phase. Each missing flag is asked via `AskUserQuestion`, one at a time, with a recommendation derived from project state.

Order and project-awareness rules:

1. **GitHub issues + PRs for this run?**
   - Probe: `gh repo view --json visibility,nameWithOwner 2>/dev/null`
   - Recommend "yes" when a remote resolves and visibility is `PRIVATE`; "no" when no remote configured or repo is public + you don't want noise
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

Each answer is echoed back as the CLI flag the user could have passed next time, e.g. "noted, equivalent to `--workers 5`". CLI flags supplied at invocation skip their corresponding prompt.

`--skip-grill` short-circuits to defaults: `workers=3`, `github=false`, `mode=interactive`, `merge-target=current-branch`, `worker-model=sonnet`, `judge-agent=false`.

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

## US-3: Worker dispatch

For each unblocked issue (`depends_on` all `merged` or empty), up to the worker cap:

1. `git worktree add .swarm/worktrees/<id> -b swarm/<id>` from the merge-target branch
2. Append `.swarm/` to `.gitignore` if not already present (commit only on first run, on a `chore(swarm): gitignore .swarm` commit)
3. Spawn a Claude Code Agent (default Sonnet) with the issue body as instructions and working directory pinned to the new worktree

Workers are dispatched as **multiple Agent tool calls in a single assistant message** so the runtime fans out. They are independent and do not coordinate.

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

At the END of the run (success or hard cap), fire `/ro:pushover` once with a one-line summary:

```
night shift done: <N> stories merged, <M> stuck, <duration>
```

Per the global Pushover firing rule for AFK runs (one notification at end, none during).

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

## See also

- `/ro:ralph` — single-agent serial sibling
- `/ro:grill-me` — upstream PRD grilling
- `/ro:write-a-prd` — PRD writer that emits `.ralph/<name>/prd.md`
- `/ro:pushover` — notification fired at end of `--afk` runs
- `/ro:drain-pr-queue` — clean up old swarm-opened PRs after the run
- `/ro:swarm` — friendly alias for this skill
- `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md` — skill-lab page with provenance
