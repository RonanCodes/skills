---
name: improve-codebase-architecture
description: Scan a repo for shallow modules and propose consolidations into deeper ones. Ousterhout's deep-modules principle applied to AI-friendly codebases (better feedback loops, easier delegation, fewer parallel-agent collisions). Standalone skill; can run on any repo. Use when a codebase feels hard for agents to work in, when modules feel too small, or before starting a Pocock Flow on a repo you haven't shaped yet. Triggers on "deepen modules", "improve architecture", "fix the module shape", "audit module depth", "what's the module map look like".
category: development
argument-hint: [--repo <path>] [--write] [--target <subdirectory>]
allowed-tools: Bash Read Write Glob Grep
---

# Improve Codebase Architecture (Deep Modules)

Matt Pocock's "one thing to take away" pitch: scan your repo for shallow modules and propose how to deepen them. Deep modules (small interface, large behaviour) are easier to test, easier to delegate to agents, and produce fewer merge conflicts when multiple agents work in parallel.

## What this skill does

1. Walks the repo's source tree.
2. For each module (file or directory), estimates **interface size** vs **behaviour size**.
3. Flags modules with low behaviour-to-interface ratio (shallow).
4. Proposes consolidations: which shallow modules could be combined into a deeper one, and what the new interface would look like.
5. Optionally writes a markdown report to `docs/architecture/module-audit.md` (with `--write`).

This skill is **read-only by default**. It proposes; the human (or a follow-up Ralph run) does the actual refactoring.

## Why this matters for AI-coding

- **Test boundaries are bigger.** One test around a deep module covers more behaviour than many tests around many shallow modules. Better feedback loops, better agent output.
- **Delegable internals.** With deep modules, the human reviews interface contracts and lets the agent own the implementation. Shallow modules force the human to track every detail because every module has roughly the same complexity-per-line.
- **Less parallel-collision.** When most coupling happens inside a module, the cross-module surface is small and stable. Multiple agents working in parallel (Sandcastle, Kanban Ralph) collide less.
- **Smaller per-task context.** An agent working inside a deep module only needs to load that module's source + the interfaces it calls. Fits the smart-zone better than tracing through ten shallow modules.

## Usage

```
/improve-codebase-architecture [--repo <path>] [--write] [--target <subdir>]
```

Defaults:
- `--repo`: current directory (resolved via `git rev-parse --show-toplevel`).
- `--write`: off; pass to persist the report.
- `--target`: scans everything; pass a subdirectory to scope the audit.

## Step 1: Discover the module map

Walk the source tree. Per language:

- TypeScript/JavaScript: each `.ts` / `.tsx` file is a module candidate. Group by directory for higher-level modules.
- Python: each `.py` file; group by package.
- Go: each `.go` file; group by package.
- Rust: each `mod` declaration.

For each module:

- **Interface size**: count exported names, total characters in the exported surface (signatures + types).
- **Behaviour size**: count total lines of code minus interface, plus any imports the module pulls in from outside its package.

## Step 2: Score depth

A rough heuristic:

```
depth_score = behaviour_size / max(interface_size, 1)
```

- `depth_score >= 8`: deep. Good shape.
- `4 <= depth_score < 8`: medium. Probably fine.
- `depth_score < 4`: shallow. Flag for review.
- Modules under 30 lines total: trivial, skip from analysis.

This heuristic is rough on purpose. Don't treat the number as truth; use it to surface candidates.

## Step 3: Propose consolidations

For each cluster of shallow modules that share callers or call each other heavily, propose a consolidation:

```
SHALLOW CLUSTER A
  - utils/format-currency.ts   (3 exports, 18 lines)
  - utils/format-date.ts        (4 exports, 22 lines)
  - utils/format-percent.ts     (2 exports, 14 lines)

PROPOSED DEEP MODULE: utils/format.ts
  Single export: format(value, type)
  Internal: all current helpers as private functions
  Test boundary: one integration test per format type
```

For each proposal, include:
- The new interface (one or two functions, narrow types).
- Where the existing internals would live.
- What test boundaries become available.
- A rough effort estimate (small / medium / large).

## Step 4: Surface "perfect-fit" candidates

Matt's killer example was wrapping a whole subsystem (browser video editor, front end to back end) in one deep module using a discriminated union between layers. Look for similar patterns:

- A subsystem with one entry point and many internal moving parts (a state machine, a workflow, a renderer).
- A module that is currently split across `client/` and `server/` but conceptually represents one operation.
- A cluster of modules that exchange a tagged-union message type but expose it through many small functions instead of one orchestrator.

These are the highest-leverage refactors. Flag them at the top of the report.

## Step 5: Write the report (if --write)

`docs/architecture/module-audit.md`:

```markdown
# Module Audit, YYYY-MM-DD

## Summary
- N modules analysed
- M flagged as shallow (depth_score < 4)
- K proposed consolidations

## High-leverage refactors (perfect-fit candidates)
...

## Shallow clusters
...

## Already-deep modules (kept for reference)
...

## How to act on this
1. Pick one proposed consolidation.
2. Run /matt-pocock-coding-workflow with the consolidation as the brief.
3. Re-run /improve-codebase-architecture after to confirm the depth_score improved.
```

## What this skill does NOT do

- It does not refactor automatically. Refactoring requires understanding context this heuristic doesn't have.
- It does not score "good" vs "bad" architecture overall. A codebase can score badly on depth and still be the right shape for its domain.
- It does not understand framework conventions (Next.js page files are shallow by design; React components are often shallow but composable). Use judgment when reviewing flagged items.

## Cross-references

- Deep modules concept → `llm-wiki-ai-research:deep-modules-for-ai`
- John Ousterhout, *A Philosophy of Software Design* (the source)
