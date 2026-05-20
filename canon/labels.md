# Canonical Label System

Single source of truth for GitHub labels across every personal repo (factory, factory-testbench, llm-wiki, lekkertaal, dataforce, and any future sibling).

The same vocabulary applies on every repo. System repos (ronan-skills, llm-wiki tooling) just don't fire the dispatch modifiers, but the labels exist there for consistency so the migration script is one-shot everywhere.

Machine-readable mirror lives next door at [`canon/labels.yml`](./labels.yml). The migration script [`scripts/migrate-labels.sh`](../scripts/migrate-labels.sh) reads the YAML.

## Lifecycle (exactly one set at all times)

| Label | Colour | Semantics | When set | When unset |
|---|---|---|---|---|
| `needs-grilling` | `FBCA04` (yellow) | Raw idea. Not a real spec yet. Day-shift picks these up to grill via AskUserQuestion. | On `/write-a-prd` if the user did not bypass the grill; on `/slice-into-issues` for any child slice whose ACs are still hand-wavy. | When day-shift finishes grilling: flip to `ready-for-agent`. |
| `ready-for-agent` | `0E8A16` (green) | Fully grilled. ACs concrete. An agent can pick this up unattended. | After day-shift finishes the grill, after `/slice-into-issues` if ACs were already concrete, or after a reviewer-reject (returns from `in-progress`). | When an orchestrator picks it up: flip to `in-progress`. |
| `in-progress` | `1D76DB` (blue) | An orchestrator (ralph / planner-worker / matt-pocock) is currently working it. | On worker pickup, before the worker opens its PR. | When the PR merges (close issue, drop the label) or work is paused (back to `ready-for-agent` or `needs-human`). |
| `needs-human` | `B60205` (red) | Blocked on a human-only action: dashboard click, billing, OAuth approval, CAPTCHA, etc. | When an agent escalates: HITL trigger fires, reviewer hard-blocks, or hard-block discovered mid-implementation. | When the human resolves the block and re-labels to `ready-for-agent`. |

The closed state is the absence of any lifecycle label. Conventional: don't relabel a closed issue.

## Kind (exactly one set)

| Label | Colour | Semantics |
|---|---|---|
| `kind:prd` | `0052CC` (dark blue) | Parent PRD. Tracks child slices via `## Parent\n\n#<N>` references in slice bodies. |
| `kind:slice` | `5EBEFF` (light blue) | Child of a PRD. The unit of work. Orchestrators pick `kind:slice + ready-for-agent`. |
| `kind:incident` | `D93F0B` (red) | Runtime regression / production incident. Skip the PRD layer, straight to slice rules. |
| `kind:chore` | `BFBFBF` (grey) | Housekeeping not tied to a PRD: CI fixes, dep bumps, label migrations, doc tweaks. |
| `kind:research` | `5319E7` (deep violet) | Research / investigation. Output is documentation, not code. Close-the-loop is a discoverable, bidirectionally-linked doc in `docs/research/` AND the LLM wiki — NOT tests. See [[canon:research-tasks]]. Orchestrators pick `kind:research + ready-for-agent` and route to the research-worker prompt. |

## Modifiers (additive flags, set as many as apply)

| Label | Colour | Semantics |
|---|---|---|
| `hitl-likely` | `D93F0B` (orange-red) | Reviewer expected to escalate. Set on slices touching ORM, schema-migration, billing, OAuth, secret rotation. Drives planner concurrency caps. |
| `parallel-eligible` | `BFE5BF` (light green) | File-disjoint from siblings. Safe to fan out concurrently in `/planner-worker`. |
| `repo-lock` | `8B0000` (dark red) | Takes a repo-wide lock (lockfile churn, schema reset, top-level config rewrite). Serial after parallel drains. |
| `bug-fix` | `8B5CF6` (purple) | Failing test committed first; implementer makes it pass. Reviewer checks the test reproduces the bug. |
| `phase-0` | `E0E0E0` | Phase marker — earliest. |
| `phase-1` | `C8C8C8` | Phase marker. |
| `phase-1.5` | `B0B0B0` | Phase marker. |
| `phase-2` | `989898` | Phase marker. |
| `phase-3` | `808080` | Phase marker — latest. |
| `from-retro` | `FFF5B1` (pale yellow) | Auto-created by a night-shift retro. Cross-repo routing pattern: a retro on repo A can open a `from-retro` slice on repo B. |
| `needs-grilling-skipped` | `FFCCCC` (pale red) | Promoted straight to `ready-for-agent` without the grill. Flag for the reviewer: ACs might be thinner than usual. |
| `deferred` | `EDEDED` (light grey) | Valid idea, parked. Orchestrators skip it regardless of lifecycle state. Doesn't break the state machine: an issue can be `ready-for-agent + deferred` (grilled but not on the schedule) or `needs-grilling + deferred` (raw idea, not now). Remove the modifier to re-enter the queue. Use this instead of closing-as-wontfix when the idea is still alive but not on the current critical path. |

## State machine

```
                                  reviewer reject
                                  ┌──────────────────────┐
                                  ▼                      │
   ┌────────────────┐  grill   ┌────────────────┐    pickup    ┌─────────────┐    PR merge
   │ needs-grilling │ ───────▶ │ ready-for-agent│ ───────────▶ │ in-progress │ ─────────────▶ (closed)
   └────────────────┘          └────────────────┘              └─────────────┘
                                       ▲                              │
                                       │ unblock                      │ HITL escalation
                                       │                              ▼
                                       └────────────────── ┌─────────────┐
                                                           │ needs-human │
                                                           └─────────────┘
```

The arrows are the only legal transitions. `/close-the-loop` is the gatekeeper between `in-progress` and closed: it asserts the verification matrix before letting the orchestrator drop the `in-progress` label.

## Repo scope

The label set is identical on every repo. There is no "system repo subset" because we want a single migration to do every repo, and we don't want a worker to discover mid-run that the label it expects doesn't exist here. System repos (ronan-skills, llm-wiki tooling) just won't have orchestrators applying `parallel-eligible` / `repo-lock` very often, but the labels exist.

## Branch flow

Workers branch off an issue via `gh issue develop` rather than plain `git checkout -b`. This produces the GitHub-side issue→branch dev-link, which makes the PR's `Closes #N` automatic and lets night-shift retros walk issue→PR without title-matching.

```
gh issue develop <issue-number> --name <slug> --checkout
```

Worker prompts in `/ralph`, `/planner-worker`, `/night-shift`, and `/matt-pocock-coding-workflow` mandate this command.

## Migration

[`scripts/migrate-labels.sh`](../scripts/migrate-labels.sh) takes a repo (owner/name) and applies the canonical label set. It is idempotent: re-running is a no-op for repos already on the canon.

```bash
./scripts/migrate-labels.sh --dry-run RonanCodes/factory   # preview
./scripts/migrate-labels.sh           RonanCodes/factory   # apply
```

The script also renames legacy labels (`lock-repo` → `repo-lock`, `expected-hitl` → `hitl-likely`, `expected-parallel` → `parallel-eligible`, `blocked-on-human` → `needs-human`) preserving the issue linkage. See the `rename_map` block in `labels.yml`.

## Changelog

- 2026-05-19 — Initial lock. Lifecycle / kind / modifiers split, state machine fixed, branch flow uses `gh issue develop`. Authoritative replacement for the ad-hoc label sets across factory, factory-testbench, llm-wiki, lekkertaal, dataforce.
- 2026-05-19 — Added `deferred` modifier. Lets the orchestrator skip valid-but-parked ideas without closing them or polluting the four-state lifecycle. Day-shift surfaced the gap when grilling dataforce #174 (admin-dashboard impersonation user-story deferred to v2).
