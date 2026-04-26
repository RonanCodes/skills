---
name: create-skill
description: Create a new Claude Code skill with proper SKILL.md structure, frontmatter, and best practices. Use when user wants to create, write, build, or add a new skill.
category: project-setup
argument-hint: [skill-name]
---

# Create a Skill

Guide the user through creating a well-structured Claude Code skill.

## Process

1. **Gather requirements** — ask the user:
   - What task or capability does the skill cover?
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
| `user-invocable` | `false` for background knowledge Claude should auto-apply. |
| `allowed-tools` | Pre-approve tools to avoid permission prompts. |
| `context` | `fork` to run in isolated subagent (no conversation history). |
| `agent` | Which subagent to use with `context: fork`. |

### Do NOT set `disable-model-invocation`

Skip this field entirely. It exists to prevent the model from auto-invoking a skill, but in practice that just makes the model fall back to bash one-liners and miss the skill's value. If you don't trust a skill's auto-invocation, the answer is to **make the description more precise** (clearer triggers, sharper "use when" phrasing), not to gate it. For genuinely destructive operations, rely on the harness permission system + `allowed-tools` scoping, not on blocking model invocation.

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

## Environment Variables (Credentials)

If a skill's script needs API tokens or other secrets, the location depends on whether the skill lives in a **plugin** or a **standalone repo**. Use the right pattern for the shape.

### A. Standalone skill (in a repo's `.claude/skills/`)

One `.env` at the **repo root**, gitignored, with `.env.example` committed. All skills in the repo share it. Mirrors Laravel/Next.js convention.

```
repo/
├── .env                             # gitignored, user's secrets
├── .env.example                     # committed template
├── .gitignore                       # contains `.env`
└── .claude/skills/<name>/
    ├── SKILL.md
    └── scripts/helper.sh            # sources `../../../.env`
```

Inside the script:
```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../.env"     # walk up: scripts/ → skill/ → skills/ → .claude/ → repo root
```

### B. Plugin skill (in a repo with `.claude-plugin/plugin.json`)

Use **`${CLAUDE_PLUGIN_DATA}/.env`** — Claude Code's documented persistent plugin-data directory. Survives plugin updates and is auto-cleaned on uninstall. For Cursor or dev mode (where the var isn't set), fall back to the explicit path.

```
plugin-repo/
├── .claude-plugin/plugin.json
├── .env.example                     # committed template with setup instructions
└── skills/<name>/scripts/helper.sh  # sources $CLAUDE_PLUGIN_DATA/.env
```

Inside the script:
```bash
#!/usr/bin/env bash
set -euo pipefail
# One-liner: CLAUDE_PLUGIN_DATA when set by Claude Code; explicit fallback otherwise
ENV_FILE="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/<plugin-id>}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: credentials not found at $ENV_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
```

Where `<plugin-id>` is the plugin's canonical id (`name@marketplace-name` with non-alphanumerics replaced by `-`).

### Why the split?

- **Standalone repo** IS where Claude loads skills from → relative `../../../.env` works reliably.
- **Plugins** get COPIED to `~/.claude/plugins/cache/...` on install → relative paths break. `${CLAUDE_PLUGIN_DATA}` is the [documented escape hatch](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory).

### Shared conventions either way

- Never commit `.env` (add to `.gitignore`; `*.env` pattern is a good default)
- Always commit `.env.example` with placeholder values as documentation
- `chmod 600` the real `.env` after creating it
- One env file per repo/plugin, shared across skills — don't create a `.env` per skill (rotation nightmare)

## Checklist

Before saving, verify:

- [ ] Description includes trigger phrases ("Use when...")
- [ ] SKILL.md is focused and under 100 lines
- [ ] No time-sensitive info that will go stale
- [ ] Concrete examples included
- [ ] `disable-model-invocation` is NOT set (never use this flag)
- [ ] Supporting files referenced from SKILL.md if they exist
- [ ] If the skill needs secrets: the right env pattern is used (repo-root `.env` for standalone, `${CLAUDE_PLUGIN_DATA}/.env` for plugin) — see "Environment Variables" section
