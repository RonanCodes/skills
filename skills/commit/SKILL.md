---
name: commit
description: Create git commits with emoji conventional commit format. Handles staging, message formatting, and timestamp rules. Use when committing changes.
category: development
disable-model-invocation: true
---

# Commit

Create well-formatted git commits with emoji conventional commit style.

## Usage

```
/commit
/commit --amend
```

## Format

Every commit message MUST use this format:

```
<emoji> <type>: <description>
```

Single line. Lowercase description. No period at the end. Focus on the "why" not the "what".

## Emoji Map

| Emoji | Type | When to use |
|-------|------|-------------|
| ✨ | feat | New feature or capability |
| 🐛 | fix | Bug fix |
| 🧪 | test | Adding or fixing tests |
| 📝 | docs | Documentation changes |
| 🧹 | chore | Maintenance, config, tooling |
| ♻️ | refactor | Code restructuring without behaviour change |
| 🚀 | deploy | Deployment-related changes |
| 🔧 | config | Configuration changes |
| ⚡ | perf | Performance improvements |
| 🔒 | security | Security fixes |

## Examples

```
✨ feat: add vault search with fuzzy matching
🐛 fix: prevent duplicate wiki pages on re-ingest
♻️ refactor: extract frontmatter parser into shared util
📝 docs: add obsidian integration guide
🧹 chore: update dependencies and clean unused imports
```

## Rules

1. Do NOT include `Co-Authored-By` lines
2. Do NOT add scope in parentheses — use `✨ feat: thing` not `✨ feat(scope): thing`
3. Use the emoji that best matches the primary intent of the change
4. If a commit spans multiple types, use the most significant one
5. Keep the description under 72 characters
6. Use imperative mood: "add" not "added", "fix" not "fixed"

## Workflow

1. Run `git status` and `git diff` to understand what changed
2. Run `git log --oneline -5` to see recent commit style
3. Stage the relevant files (prefer specific files over `git add -A`)
4. Draft the commit message following the format above
5. Check if there are timestamp rules in the project's CLAUDE.md — if so, apply `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`
6. Commit and verify with `git status`

## Passing `--amend`

If the user passes `--amend`, amend the previous commit instead of creating a new one. Preserve the original timestamp unless the user specifies otherwise.
