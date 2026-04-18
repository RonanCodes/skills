---
name: git-guardrails
description: Safety net that blocks destructive git commands and suggests safer alternatives. Background knowledge for configuring pre_tool_use hooks.
category: quality
user-invocable: false
---

# Git Guardrails

Hook configuration that intercepts destructive git commands before they execute, warns the user, and suggests safer alternatives.

## Destructive Commands to Block

| Command | Risk | Safer Alternative |
|---------|------|-------------------|
| `git push --force` | Overwrites remote history, can destroy teammates' work | `git push --force-with-lease` |
| `git push --force` to main/master | **Never do this** — can break CI, deployments, everyone's local | Create a PR instead |
| `git reset --hard` | Discards all uncommitted changes permanently | `git stash` then `git reset --soft` |
| `git clean -f` | Deletes untracked files permanently | `git clean -n` (dry run first) |
| `git branch -D` | Force-deletes branch even if unmerged | `git branch -d` (safe delete, warns if unmerged) |
| `git checkout -- .` | Discards all unstaged changes | `git stash` to preserve changes |
| `git restore .` | Discards all working tree changes | `git stash` or restore specific files |

## Hook Configuration

Add this to `.claude/settings.json` or `~/.claude/settings.json`:

```json
{
  "hooks": {
    "pre_tool_use": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'CMD=\"$CLAUDE_TOOL_INPUT\"; BLOCKED=\"\"; if echo \"$CMD\" | grep -qE \"git\\s+push\\s+.*--force\" && ! echo \"$CMD\" | grep -qE \"\\-\\-force-with-lease\"; then BLOCKED=\"git push --force\"; elif echo \"$CMD\" | grep -qE \"git\\s+reset\\s+--hard\"; then BLOCKED=\"git reset --hard\"; elif echo \"$CMD\" | grep -qE \"git\\s+clean\\s+-[a-zA-Z]*f\"; then BLOCKED=\"git clean -f\"; elif echo \"$CMD\" | grep -qE \"git\\s+branch\\s+-D\"; then BLOCKED=\"git branch -D\"; elif echo \"$CMD\" | grep -qE \"git\\s+checkout\\s+--\\s+\\.\"; then BLOCKED=\"git checkout -- .\"; elif echo \"$CMD\" | grep -qE \"git\\s+restore\\s+\\.\"; then BLOCKED=\"git restore .\"; fi; if [ -n \"$BLOCKED\" ]; then echo \"BLOCKED: $BLOCKED detected. See git-guardrails skill for safer alternatives.\"; exit 1; fi'"
          }
        ]
      }
    ]
  }
}
```

## What the Hook Does

1. **Intercepts** every `Bash` tool call before execution
2. **Pattern-matches** against known destructive git commands
3. **Blocks** the command with exit code 1, which prevents execution
4. **Displays** a warning explaining what was caught

## Patterns Matched

- `git push` with `--force` (but NOT `--force-with-lease`, which is safe)
- `git reset --hard`
- `git clean` with `-f` flag
- `git branch -D` (uppercase D = force delete)
- `git checkout -- .` (discard all changes)
- `git restore .` (discard all changes)

## Overriding the Hook

If you genuinely need to run a blocked command, you can:

1. **Temporarily remove** the hook from settings.json, run the command, add it back
2. **Run the safer alternative** suggested in the table above
3. **Be specific** instead of broad — e.g., `git checkout -- single-file.txt` instead of `git checkout -- .`

## Installation

Copy the hook configuration above into your preferred settings file:

- **Per-project:** `.claude/settings.json` (committed, team-wide)
- **Personal:** `~/.claude/settings.json` (applies to all projects)
