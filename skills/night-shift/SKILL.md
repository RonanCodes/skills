---
name: night-shift
description: Zero-config night-shift swarm against the current repo's GitHub backlog. Run inside any gh-remote repo to dispatch `/ro:planner-worker --afk` (or `/ro:ralph --afk` with `--build ralph`) against the existing `ready-for-agent` slice issues. Auto-detects the current repo, verifies there are unblocked slices to work on, inherits Opus reviewer + Pushover-when-done defaults, and skips the US-0 grilling phase. Use when you just want to kick off the night-shift swarm against the backlog in this repo with zero flags.
category: development
argument-hint: [--build swarm|ralph] [--workers <N>] [--label <label>] [--no-ping] [--plan-only]
allowed-tools: Bash Read Agent
---

# /ro:night-shift

The "swarm the factory" trigger. Zero-arg by default. Run inside any repo with a `gh` remote and pre-sliced `ready-for-agent` issues.

This is the shortest path between "I'm going to bed" and "the swarm is working".

## What it does

1. **Pre-flight current repo.** Run `gh repo view --json url,defaultBranchRef` to confirm there's a gh remote. If not → fail loudly with a pointer to `gh repo create`.
2. **Resolve the queue label.** Default `ready-for-agent`. Override via `--label <name>`. Also check `docs/agents/triage-labels.md` for a project-local synonym (e.g. Pocock's `Sandcastle`) — if present, use that.
3. **Count open slice issues.** `gh issue list --state open --label <label> --json number,body`. Filter to slices (body opens with `## Parent\n\n#<N>` — skip parent PRDs which open with `## Problem Statement`).
4. **Sanity-check there's unblocked work.** Parse `## Blocked by` sections. If ALL slices are blocked → fail with a list of the blocking issues.
5. **Dispatch the swarm.** By default:
   ```
   /ro:planner-worker --afk --source github:<label>
   ```
   With `--build ralph`:
   ```
   /ro:ralph --afk --source github:<label> --mode fresh
   ```
6. **Return.** The dispatched skill handles everything else: planner emits dep graph, workers fan out in worktrees, merger reviews on Opus 4.7, Pushover fires at end via global CLAUDE.md rule 4 (or skill-level default, both fire). Don't tail logs — let it run.

## Defaults inherited from ronan-skills ≥ 1.46.1

- `--source github:<label>` — read from current repo's GH backlog
- `--reviewer opus` (when `--build ralph`) or Opus merger (when `--build swarm`)
- `--afk` — auto-approve config, judge-agent termination, skip grilling
- `--workers 3` — concurrent cap (per Max 20x weekly limits memory)
- Pushover at end — confirmed in global `~/CLAUDE.md` § Pushover Notifications rule 4

Override any by passing the flag explicitly.

## Quick start

```
cd ~/Dev/ai-projects/factory
/ro:night-shift                          # Parallel swarm, Opus reviewer, ping when done
/ro:night-shift --build ralph            # Serial Ralph loop instead (use when slices are dep-chained)
/ro:night-shift --workers 5              # Override default 3 parallel workers (be careful with Max cap)
/ro:night-shift --label Sandcastle       # Custom queue label (Pocock synonym example)
/ro:night-shift --no-ping                # Skip the Pushover notification
/ro:night-shift --plan-only              # Dry-run: show what would dispatch, no actual run
```

## Why this exists

`/ro:swarm` and `/ro:planner-worker` both open with the US-0 grilling phase unless you pass `--afk`. That grilling is correct for first-time-in-a-repo runs where you genuinely don't know the worker count or whether you want a judge agent.

For unattended overnight runs against a known, already-sliced backlog, the grilling is friction. `/ro:night-shift` removes it. The user's "night shift the factory" vocabulary becomes the literal command.

## When NOT to use

- **No backlog yet.** Run `/ro:write-a-prd` + `/ro:slice-into-issues` first (or `/agentic-e2e-flow` for the full pipeline).
- **First time in a repo with unknown config.** Use `/ro:swarm` to grill on worker count, judge-agent, etc., then come back to `/ro:night-shift` once defaults are set in `.swarm.json`.
- **Single-story exploration.** Use `/ro:ralph --mode single` to chew on one story without committing to a full loop.
- **Untrusted code or hostile input.** No container isolation; future `--sandcastle` flag pending.

## Errors

| Condition | Message |
|---|---|
| No gh remote | "Not in a gh-remote repo. `/ro:night-shift` requires a GitHub remote. Run `gh repo create` to add one." |
| Zero open slices with the label | "No `<label>` issues found in this repo. Run `/ro:write-a-prd` + `/ro:slice-into-issues` to populate the backlog (or use `/agentic-e2e-flow` for the full pipeline)." |
| All slices blocked | "All `<label>` slices are blocked. Blocked by: #N, #M, #K. Resolve those first or unblock manually." |
| `--build ralph` with parallel-eligible slices | "Heads-up: most of your slices look parallel-eligible. `--build swarm` would finish faster. Continue with serial Ralph? (y/N)" — if interactive; auto-continue if `--afk` was forced via env. |

## See also

- `/ro:planner-worker` (alias `/ro:swarm`) — the parallel swarm this dispatches to. Use directly when you want the US-0 grilling phase.
- `/ro:ralph` — the serial loop alternative. Dispatched via `--build ralph`.
- `/ro:write-a-prd` — upstream step that publishes the parent PRD as a GH issue.
- `/ro:slice-into-issues` — upstream step that breaks the PRD into `ready-for-agent`-labelled child issues.
- `/agentic-e2e-flow` — full end-to-end pipeline from research to ship. Use when you also need the upstream PRD + slice phases.
- `/ro:pushover` — fired at end of run per global rule.

## Provenance

Created 2026-05-14 in response to user request: "If I'm in a repo I want a forward slash command that auto runs the night-shift swarm with sub-agent planners and sub-agent workers against the existing GH backlog for the current repo we are in."

Built on top of `/ro:planner-worker` (the actual swarm logic) and the auto-pushover + Opus-reviewer defaults locked in ronan-skills 1.46.1 the same day.
