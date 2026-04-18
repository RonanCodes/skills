---
name: ralph
description: Run an autonomous Ralph loop to implement tasks from a PRD in .ralph/. Picks the highest priority incomplete story, implements it, validates, commits, and updates progress. Supports named PRDs (e.g. one per project phase) via --prd <name>. Use when you want to start the Ralph loop, run ralph, or implement PRD tasks autonomously.
argument-hint: [--prd <name>] [--plan-only | --single | --all]
disable-model-invocation: true
allowed-tools: Bash(git *) Read Write Edit Glob Grep
---

# Ralph Loop

Autonomous coding agent loop based on the Ralph Wiggum technique. Each iteration picks one task from a PRD file under `.ralph/`, implements it, validates, commits, and updates progress.

## Quick Start

```
/ralph                        # Run one iteration from .ralph/prd.json
/ralph --prd phase-2a         # Run one iteration from .ralph/prd-phase-2a.json
/ralph --prd phase-2a --all   # Run every remaining story in that PRD
/ralph --plan-only            # Show what would be done next (no changes)
```

## PRD File Resolution

The `--prd <name>` flag selects which PRD file to work from:

- `--prd <name>` → reads `.ralph/prd-<name>.json` and writes progress to `.ralph/progress-<name>.txt`
- no flag → reads `.ralph/prd.json` and writes progress to `.ralph/progress.txt` (legacy / single-PRD projects)

This lets one repo drive multiple concurrent phases/initiatives without progress-file collisions. Each named PRD is independent: its own story list, its own branchName, its own progress log.

**Naming convention:** use kebab-case slugs tied to the phase or initiative — `phase-2a`, `phase-2b-presentation`, `auth-migration`, `docs-refresh`. The slug must match `[a-z0-9-]+`.

**Shared Codebase Patterns:** if `.ralph/patterns.md` exists, treat it as global learnings read on every iteration regardless of which PRD is active. Individual progress files still carry the per-iteration detail.

## How It Works

1. Resolve PRD file from `--prd` flag (or default `.ralph/prd.json`) — find the highest priority story where `passes: false`
2. Read the matching progress file (and `.ralph/patterns.md` if present) — check Codebase Patterns section for learnings from prior iterations
3. Implement the story
4. Validate (typecheck, lint, test — whatever the project requires)
5. Commit with message: `feat: [Story ID] - [Story Title]`
6. Update the PRD file — set `passes: true` for completed story
7. Append progress to the matching progress file with learnings

## One Story Per Iteration

Work on ONE story at a time. After completing it, stop. The next `/ralph` invocation (or loop iteration) picks up the next story with a fresh context.

## Progress Report Format

APPEND to the matching progress file (never replace). The progress file is `.ralph/progress-<name>.txt` when `--prd <name>` is used, otherwise `.ralph/progress.txt`:

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

If ALL complete: report "All tasks complete!" and stop.

If more remain and `--all` flag: continue to next story.

If more remain and no `--all` flag: stop after the single story (default).

## PRD File Format (prd.json or prd-<name>.json)

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
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Story Size Rule

Each story must be completable in ONE iteration (one context window). If a story is too big, split it before running.

Right-sized: "Create vault-create skill with SKILL.md"
Too big: "Build the entire ingest system"
