---
name: ralph
description: Run an autonomous Ralph loop to implement tasks from .ralph/prd.json. Picks the highest priority incomplete story, implements it, validates, commits, and updates progress. Use when you want to start the Ralph loop, run ralph, or implement PRD tasks autonomously.
argument-hint: [--plan-only | --single | --all]
disable-model-invocation: true
allowed-tools: Bash(git *) Read Write Edit Glob Grep
---

# Ralph Loop

Autonomous coding agent loop based on the Ralph Wiggum technique. Each iteration picks one task from `.ralph/prd.json`, implements it, validates, commits, and updates progress.

## Quick Start

```
/ralph              # Run one iteration (default)
/ralph --all        # Run all remaining tasks
/ralph --plan-only  # Just show what would be done next
```

## How It Works

1. Read `.ralph/prd.json` — find the highest priority story where `passes: false`
2. Read `.ralph/progress.txt` — check Codebase Patterns section for learnings from prior iterations
3. Implement the story
4. Validate (typecheck, lint, test — whatever the project requires)
5. Commit with message: `feat: [Story ID] - [Story Title]`
6. Update `.ralph/prd.json` — set `passes: true` for completed story
7. Append progress to `.ralph/progress.txt` with learnings

## One Story Per Iteration

Work on ONE story at a time. After completing it, stop. The next `/ralph` invocation (or loop iteration) picks up the next story with a fresh context.

## Progress Report Format

APPEND to `.ralph/progress.txt` (never replace):

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

If you discover a reusable pattern, add it to the `## Codebase Patterns` section at the TOP of `.ralph/progress.txt` (create it if missing):

```
## Codebase Patterns
- Skills use SKILL.md format with YAML frontmatter
- Vault CLAUDE.md files are thin config, not logic
- Use wikilinks [[page]] syntax for cross-references
```

Only add patterns that are general and reusable, not story-specific.

## Stop Condition

After completing a story, check if ALL stories have `passes: true`.

If ALL complete: report "All tasks complete!" and stop.

If more remain and `--all` flag: continue to next story.

If more remain and no `--all` flag: stop after the single story (default).

## .ralph/prd.json Format

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
