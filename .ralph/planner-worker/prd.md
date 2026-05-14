# PRD: /ro:planner-worker

Status: draft, ready for review
Owner: Ronan
Date: 2026-05-14

## Problem

Multi-agent coding is the new ceiling on throughput. Cursor showed it scales (browser swarm: ~1M LoC, ~1,000 files, hundreds of workers, one week). Matt Pocock showed it can run on one developer's laptop via Sandcastle: planner + worker per Docker-sandboxed worktree + merger agent, day-shift / night-shift split. Neither pattern exists as a reusable skill in `ronan-skills` today. `/ro:ralph` is single-agent serial; `/ro:grill-me` + `/ro:write-a-prd` cover the upstream half. The gap is the multi-agent execution layer that takes a grilled PRD and dispatches parallel workers against it.

This skill closes that gap. It is the multi-agent sibling to `/ro:ralph`, sized for one developer's projects (3-10 workers) with a path to autonomous overnight runs.

## Why not Sandcastle

Sandcastle is the closest existing implementation but it requires `ANTHROPIC_API_KEY` and bills as API usage. Issue mattpocock/sandcastle#191 ("use Claude subscription instead of `ANTHROPIC_API_KEY`") is marked **wontfix**. Even routing `claude setup-token`'s long-lived OAuth into a Sandcastle container does not solve it (anthropics/claude-code#43333: headless `claude -p` with OAuth still bills as API, not Max).

v1 of this skill therefore runs on Claude Code's **native Agent tool**, which inherits the parent session's auth (so it bills against the user's Max plan), and uses **plain `git worktree`** for isolation (no Docker). Trade-off: workers share the host filesystem. The mitigation is the merger agent reviewing diffs before merge, not container isolation. If we ever need hostile-code sandboxing or cross-machine fanout, a future `--sandcastle` flag wraps the same skill around Sandcastle.

## Goal

Ship `/ro:planner-worker` (alias `/ro:swarm`) as a new skill in `ronan-skills` that, given a grilled PRD on disk, runs a planner → worker swarm with merger agent and produces merged commits on the user's main branch.

Definition of done for v1:
- `cd <repo-with-grilled-prd> && /ro:planner-worker` ends with the backlog implemented, tests + types green, and either commits on `main` (default) or open PRs to merge (with `--github`)
- One real demo run against `lekkertaal` with at least 3 vertical-slice issues completed
- Skill page published to `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md`

## Non-goals (v1)

- Not building a runtime daemon, web UI, or hosted control plane. CLI invocation only
- Not implementing Cursor's full "hundreds of agents on a shared branch" model. Worktree isolation only
- Not designing a new PRD format. Read whatever `/ro:write-a-prd` emits
- Not solving cross-repo or monorepo coordination
- Not replacing `/ro:ralph`. The single-agent serial loop stays for one-shot tasks
- Not wrapping Sandcastle or shipping any Docker / Node dependency. Bash + git + Claude Code Agent tool only

## Prereqs

- `git` (`worktree` subcommand, ships with git)
- Claude Code with the Agent tool (this skill runs inside a Claude Code session)
- `gh` CLI authenticated, only if the user picks `--github` mode
- That's it. No Docker, no Node, no API key

## User stories

### Config

**US-0: Interactive config phase before anything runs.** When invoked without all flags supplied, the skill opens with a project-aware grilling phase (per the shared `feedback-skill-flags-grilling` principle). Each flag is prompted one at a time via `AskUserQuestion` with a recommendation derived from project state:

- "GitHub issues + PRs for this run?" [recommended: yes, `gh repo view` resolved and remote is private / no, no remote configured]
- "Worker count?" [recommended: 3, based on cores and free disk on `.swarm/worktrees/`]
- "Run mode?" [recommended: interactive, you're at-keyboard / AFK, you said `kick off and ping me`]
- "Merge target?" [recommended: current branch / staging branch `swarm-staging`]
- "Worker model?" [recommended: sonnet]
- "Add a Judge agent at end of each cycle?" [recommended: no for a defined PRD / yes for an open-ended goal]

Each answer is echoed back as the equivalent CLI flag the user could have passed, so the user learns the surface over time. CLI flags supplied at invocation skip their corresponding prompt. `--skip-grill` skips the whole phase and uses defaults (intended for scripted/ralph runs).

### Core flow

**US-1: Plan from a grilled PRD.** As a developer with a finished `.ralph/<name>/prd.md`, I can run `/ro:planner-worker --prd <name>` and the planner agent (Opus, invoked via Agent tool) reads the PRD, explores the codebase, and emits a backlog of vertical-slice issues to `.ralph/<name>/issues/*.md`. The planner exits after dispatch and is not re-invoked unless a worker fails.

**US-2: Confirm the backlog before dispatch.** After the planner emits the backlog, the skill pauses and shows the user a one-screen summary (issue count, titles, dependency graph). User confirms with `y` or rejects with feedback. Rejecting re-runs the planner with the feedback as context. Skip with `--auto-approve` or AFK mode.

**US-3: Dispatch workers in plain git worktrees.** On confirmation, for each unblocked issue (up to N, default 3, cap via `--workers N`, hard ceiling 10):

1. `git worktree add .swarm/worktrees/<issue-id> -b swarm/<issue-id>`
2. Spawn a Claude Code Agent (Sonnet) with the issue body, working directory pinned to the new worktree, and the project's relevant CLAUDE.md / skill conventions in scope
3. Worker is told its DoD commands and is required to exit only on green

Workers run in parallel via multiple Agent tool invocations in one assistant message. They do not coordinate with each other.

**US-4: Worker exits only on green DoD.** A worker exits successfully only when the project's DoD commands pass on its worktree. Default DoD: auto-detected from `package.json` (`pnpm test` + `pnpm typecheck`, or `npm test` + `tsc --noEmit`). Per-repo override via `.swarm.json` lets the project add lint, integration tests, or a `verify-quick.sh`-style script.

**US-5: Merger agent reviews + merges clean worktrees.** When a worker exits green, a merger Agent (Opus) reviews the worker's diff against the issue spec, then performs:

1. `cd .swarm/worktrees/<issue-id> && git rebase <merge-target>`
2. If rebase clean and DoD still passes: `cd <repo-root> && git merge --no-ff swarm/<issue-id>` (or `gh pr merge --squash` in `--github` mode)
3. `git worktree remove .swarm/worktrees/<issue-id>` and `git branch -D swarm/<issue-id>` on success
4. On any failure: leave worktree in place for forensics and escalate

Merge target defaults to the current branch at skill invocation. `--staging-branch <name>` routes merges to that branch instead, with main updated only on user-initiated final merge.

**US-6: Escalate conflicts and failures to the human.** If merge conflicts arise, or tests fail after rebase, the merger agent stops and posts a one-line summary to stdout + `.swarm/status.md`. The user resolves manually, then runs `/ro:planner-worker --resume` to continue.

**US-7: Worker failure triggers planner re-plan.** If a worker fails its DoD (after one retry with the failure context as added input), the issue is marked stuck. The planner is re-invoked with the failure log and is allowed to re-decompose the failed issue into smaller issues, which replace the failed one in the backlog. This is the only path that re-invokes the planner mid-run.

### Flags (each is grilled in US-0 unless passed)

**US-8: `--github` mirrors to real GitHub.** With `--github`, the planner additionally opens real GitHub issues in the current repo (one per backlog item via `gh issue create`). Workers push their branch and open real PRs via `gh pr create`. The merger agent reviews + merges (or escalates to human review) via `gh pr merge --squash`. The skill exits when the backlog is empty.

**US-9: `--judge-agent` upgrades to Cursor-mode termination.** Default termination: the skill exits when the backlog is empty. With `--judge-agent`, an Opus Judge Agent runs at the end of each dispatch cycle and decides "keep going" (re-invoke the planner to look for missed work) or "stop." This is the long-running autonomous mode for ambiguous goals. Bounded by `--max-cycles N` (default 10) and `--max-runtime <duration>` (default 4h).

**US-10: `--afk` is the autonomous combination.** `--afk` implies `--auto-approve --judge-agent --skip-grill` and fires `/ro:pushover` once at the very end of the run with a one-line summary (stories merged, stories stuck, total wall time). Per the global Pushover firing rule for AFK runs.

**US-11: `--workers N` caps concurrency.** N defaults to 3. Maximum 10 without `--unsafe-many`. Above 10 the skill warns about laptop thermals + git worktree disk usage and requires the flag.

**US-12: `--resume` picks up after human intervention.** After a human-escalation, `--resume` re-reads `.swarm/status.md` and re-dispatches any unmerged workers + retries the failed merges. Idempotent.

### Visibility

**US-13: Live status to stdout + status file.** During the run, each worker logs to `.swarm/logs/<issue-id>.log`. A top-level `.swarm/status.md` is rewritten on every state change with: current cycle, workers active, issues merged, issues stuck, last 5 events. Tail-friendly for monitoring from a second terminal.

**US-14: Postmortem on exit.** On exit (success or stop), the skill writes `.swarm/run-<timestamp>.md` summarizing: PRD title, total wall time, issues planned, issues merged, issues stuck, total commits, links to each merged commit (and each open PR if `--github`).

### Documentation + dogfooding

**US-15: Skill page in skill-lab vault.** Add `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md` documenting the skill, with cross-vault links into `[[ai-research:cursor-planner-worker-judge]]` and `[[ai-research:phase-n-ralph-loop]]`.

**US-16: First real run against lekkertaal.** Ship the skill, then run it for real against the `lekkertaal` repo with a freshly grilled PRD covering at least three vertical-slice features. Record the run output (logs + commit hashes + wall time) as a source-note in `llm-wiki-skill-lab`.

**US-17: `/ro:swarm` alias.** The primary skill name is `/ro:planner-worker` (explicit, easy to discover). `swarm` is the friendly alias. Ship both:

1. Add the word **swarm** to the skill's `description:` frontmatter so the Skill tool's fuzzy matcher resolves `/ro:swarm`, "swarm coding", or "kick off the swarm" to this skill (description starts: "Multi-agent coding swarm. Planner / worker / merger over git worktrees on the Max plan...").
2. Ship a thin redirect skill at `~/Dev/ronan-skills/skills/swarm/SKILL.md` whose body is a one-paragraph pointer to `/ro:planner-worker` so typing `/ro:swarm` directly works as a hard alias too, with no behavioural divergence.
3. The skill page in `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md` notes the alias up front.

If the two-skill approach proves messy in practice (e.g. duplicated docs drift), collapse to description-only in v1.1.

## Architecture

```
.ralph/<name>/prd.md
        │
        ▼
   ┌────────────┐   plans backlog,    ┌──────────────────────┐
   │  Planner   │ ───── exits  ─────▶ │  .ralph/<name>/      │
   │ (Opus,     │                     │   issues/*.md        │
   │  Agent)    │                     └──────────┬───────────┘
   └────────────┘                                │
        ▲                                        ▼
        │                              ┌──────────────────┐
        │  re-plan on worker failure   │  Dispatcher      │
        │                              │  git worktree    │
        │                              │  add ×N          │
        │                              └──────┬───────────┘
        │                                     │
        │                spawn N Agents,      │
        │                one per worktree     ▼
        │                              ┌──────────────────┐
        │                              │  Worker (Sonnet, │
        │                              │  Agent tool)     │
        │                              │  1 issue, 1 wt   │
        │                              │  test+types DoD  │
        │                              └──────┬───────────┘
        │                                     │ on green
        │                                     ▼
        │                              ┌──────────────────┐
        │                              │  Merger (Opus,   │
        │                              │  Agent tool)     │
        │                              │  rebase + merge  │
        │   on stuck after retry       │  or escalate     │
        └──────────────────────────────┴──────┬───────────┘
                                              │
                                              ▼
                                       <merge-target>
                                       (or `gh pr merge`)
```

Optional `--judge-agent` runs at the end of each cycle to decide loop continuation. Every box labelled "Agent" is a Claude Code Agent tool invocation, so auth flows from the parent session.

## File layout (in the user's repo)

```
.ralph/<name>/
  prd.md                    ← already exists, written by /ro:write-a-prd
  issues/
    001-schema-points.md
    002-service-award.md
    003-dashboard-tile.md

.swarm/
  swarm.json                ← per-repo config (DoD commands, override models)
  worktrees/                ← active git worktrees (auto-cleaned on success)
    001-schema-points/
    002-service-award/
  logs/
    001-schema-points.log
    002-service-award.log
  status.md                 ← live state
  run-2026-05-14T07-30.md   ← postmortem
```

Add `.swarm/` to `.gitignore` (skill does this automatically on first run).

## Per-repo config (`.swarm.json`)

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

Sensible defaults if the file is absent: auto-detect test runner, models as listed above, 3 workers, no GitHub, merge target is the branch the skill was invoked from.

## Open questions

- **Worktree disk usage.** A 1GB node_modules × 5 worktrees is 5GB. Symlink `node_modules` from the main worktree? Risk of corruption from concurrent install. v1: do not symlink, document the disk cost.
- **Issue ID scheme.** Zero-padded sequence (001, 002...) or content-hash slugs? Sequence is simpler; hash is stable across re-plans. v1: sequence.
- **Dependency graph encoding.** Does the planner emit explicit `depends_on:` frontmatter in each issue file, or is the dispatcher graph-blind and just picks any "open" issue? v1: explicit `depends_on:`; dispatcher honours it.
- **`--github` repo discovery.** Assume `gh repo view` resolves to the current repo. Fail loudly if not.
- **Merger authority on `main`.** v1: merges directly to the merge target (default = invoking branch, matches how `/ro:ralph` works today). `--staging-branch` covers the paranoid mode.
- **Native Agent fan-out limits.** Claude Code's Agent tool fans out via multiple tool calls in one assistant message. Need to confirm the practical concurrency ceiling on Max plan (token-budget and rate-limit constraints) before promising 10 workers. v1: ship with default 3, validate the ceiling empirically during the `lekkertaal` run.

## Out of scope for v1

- Cross-repo orchestration
- Persistent run state across restarts beyond `--resume` from `.swarm/status.md`
- Web UI / dashboard
- Cursor-style shared-branch workers (the `--judge-agent` flag is the only Cursor-ism)
- Auto-grading of agent output quality (future: integrate `/rubric`)
- Sandcastle / Docker container isolation (future: `--sandcastle` flag if hostile-code or cross-machine ever required)

## Risks

- **Worktree explosion on big projects.** Mitigated by hard cap of 10 workers and disk-cost warning. Long-term: investigate npm/pnpm workspace tricks or shared store reuse.
- **Merge conflict storms when issues touch the same files.** Mitigated by the planner's `depends_on` graph, which serialises hot-file issues. Residual risk: planner gets the graph wrong. Fallback: merger escalates to human.
- **Judge agent says "keep going" forever.** Mitigated by `--max-runtime` (default 4 hours) and `--max-cycles` (default 10).
- **Filesystem damage from a runaway worker.** Workers share the host FS (no container isolation). Mitigated by: each worker only writes inside its own worktree; merger reviews diffs before merge; `--sandcastle` is the escape hatch if this ever bites.
- **Agent concurrency ceiling.** The Max plan's effective parallel-Agent count may be lower than the worker cap. Validate during the first `lekkertaal` run, document, lower defaults if needed.
- **Cost.** Runs on Max plan via Agent tool, so cost is plan-bounded not API-metered. No per-run budget cap needed in v1.

## Acceptance criteria (the "we shipped" tests)

1. `/ro:planner-worker --prd lekkertaal-pwa-bootstrap` against a fresh clone of `lekkertaal` with a 5-story PRD: all 5 stories merged to main with tests green, total wall time under 90 minutes, no human intervention required beyond initial backlog confirmation.
2. `--github` mode opens 5 real PRs against `lekkertaal`, each with a sensible title + body, and merges them via `gh pr merge --squash`.
3. `--afk` mode runs the same PRD overnight and fires Pushover at end with `night shift done, 5 stories merged, 0 stuck, 47 min`.
4. Invoking the skill without flags opens the US-0 grilling phase, asks at least 5 questions with project-aware recommendations, and proceeds based on answers.
5. Documented in `vaults/llm-wiki-skill-lab/wiki/skills/planner-worker.md` with cross-vault links to the planner-worker-judge concept and Phase N concept.
6. Skill source committed and pushed to `ronan-skills`. Version bump tagged. Cache re-syncs.
7. Both `/ro:planner-worker` and `/ro:swarm` resolve to the same behaviour (test: `/ro:swarm --help` and `/ro:planner-worker --help` produce identical output).
