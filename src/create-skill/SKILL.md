---
name: create-skill
description: Create a new Claude Code skill with proper SKILL.md structure, frontmatter, and best practices. Use when user wants to create, write, build, or add a new skill.
argument-hint: [skill-name]
disable-model-invocation: true
---

# Create a Skill

Guide the user through creating a well-structured Claude Code skill.

## Process

1. **Gather requirements** — ask the user:
   - What task or capability does the skill cover?
   - Should it be user-invoked only (`/skill-name`) or also auto-triggered by Claude?
   - Does it need shell scripts, templates, or reference files?
   - Where should it live? (project `.claude/skills/`, personal `~/.claude/skills/`)

2. **Create the skill directory and SKILL.md** following the structure below.

3. **Review with user** — present the draft, ask if anything is missing or unclear.

## Skill Directory Structure

```
skill-name/
├── SKILL.md           # Main instructions (required, under 100 lines ideally)
├── reference.md       # Detailed docs (if SKILL.md would exceed 100 lines)
├── examples.md        # Usage examples (if helpful)
└── scripts/           # Utility scripts (if deterministic operations needed)
    └── helper.sh
```

## SKILL.md Template

```yaml
---
name: skill-name
description: What the skill does in one sentence. Use when [specific trigger phrases and contexts].
argument-hint: [expected-arguments]        # optional
disable-model-invocation: true             # set true for user-only actions
user-invocable: false                      # set false for background knowledge only
allowed-tools: Bash(git *) Read            # optional, pre-approve specific tools
context: fork                              # optional, run in isolated subagent
agent: Explore                             # optional, which subagent type
---

# Skill Name

Brief description of what this does.

## Usage

\`\`\`
/skill-name <arguments>
\`\`\`

## Steps

1. First step
2. Second step
3. Third step
```

## Description Best Practices

The description is the **only thing Claude sees** when deciding which skill to load. It's critical.

- **Max 250 chars** (truncated beyond that in skill listing)
- **First sentence**: what the skill does
- **Second sentence**: "Use when [specific triggers]"
- **Include trigger phrases**: keywords users would naturally say
- **Write in third person**

Good: `"Extract transcript from YouTube videos as clean text. Use when user shares a youtube.com link and wants the content transcribed or summarized."`

Bad: `"Helps with YouTube videos."`

## Frontmatter Fields

| Field | When to use |
|-------|------------|
| `name` | Always. Lowercase, hyphens, max 64 chars. |
| `description` | Always. This is how Claude finds the skill. |
| `argument-hint` | When the skill takes arguments. Shows in autocomplete. |
| `disable-model-invocation` | `true` for actions with side effects (deploy, commit, send). |
| `user-invocable` | `false` for background knowledge Claude should auto-apply. |
| `allowed-tools` | Pre-approve tools to avoid permission prompts. |
| `context` | `fork` to run in isolated subagent (no conversation history). |
| `agent` | Which subagent to use with `context: fork`. |

## Dynamic Context

Inject live data with `` !`command` `` syntax (runs before Claude sees the content):

```markdown
## Current state
- Branch: !`git branch --show-current`
- Status: !`git status --short`
```

## When to Split Files

- SKILL.md exceeds 100 lines -> move details to reference.md
- Content has distinct domains -> separate reference files
- Advanced features rarely needed -> separate file, link from SKILL.md

## When to Add Scripts

- Operation is deterministic (validation, formatting, data extraction)
- Same code would be generated repeatedly by Claude
- Errors need explicit handling

Scripts save tokens and improve reliability vs Claude generating code each time.

## Checklist

Before saving, verify:

- [ ] Description includes trigger phrases ("Use when...")
- [ ] SKILL.md is focused and under 100 lines
- [ ] No time-sensitive info that will go stale
- [ ] Concrete examples included
- [ ] `disable-model-invocation` set correctly
- [ ] Supporting files referenced from SKILL.md if they exist
