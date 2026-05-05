---
name: context
description: Switch the active credential profile for ronan-skills. Three-tier resolver picks the right `~/.claude/.env.<context>` file based on `$RO_CONTEXT` env var, manual override, `.ro-context.local` / `.ro-context` files in the cwd or any ancestor, cwd-glob rules in `~/.claude/contexts.json`, or the default. Skills source via `$(ro context env)` to get a cwd-aware credential file. Use when the user wants to switch credentials between contexts (personal / work / per-client), set up a new context, or debug which context resolved.
category: project-setup
argument-hint: [show | where | env | list | use <name> | auto | init | add-rule <glob> <name> | diff <a> <b>]
allowed-tools: Bash(ro *) Bash(jq *) Bash(cat *) Bash(grep *) Read AskUserQuestion
---

# context — credential profile switching

`ro context` is the meta-CLI all other ronan-skills lean on for credential discovery. The actual script lives at `skills/context/scripts/ro` (in this repo) and is symlinked into `~/.local/bin/ro` so it's invokable from any terminal as `ro context …`.

This SKILL.md is the user-facing documentation. The script's `--help` is the canonical command reference.

## Quick answers

| Question | Command |
|---|---|
| What context am I in right now? | `ro context show` |
| Why this context (which rule fired)? | `ro context where` |
| Which env file did the resolver pick? | `ro context env` |
| Which contexts exist? | `ro context list` |
| Switch context for the rest of my session | `ro context use <name>` |
| Stop pinning, go back to cwd-resolution | `ro context auto` |
| First-time setup | `ro context init` |
| Add a cwd-glob auto-rule | `ro context add-rule '~/Github-Acme/**' acme` |

## Resolution chain (highest priority first)

1. **`$RO_CONTEXT` env var** — one-shot per shell, never written to disk.
2. **`contexts.json:active`** — manual override set by `ro context use`. Sticky until cleared by `ro context auto`.
3. **`.ro-context.local`** in cwd or any ancestor — gitignored contributor override.
4. **`.ro-context`** in cwd or any ancestor — committed, repo's declared context. **Recommended default for any repo with a stable owner/account.**
5. **cwd-glob rule** in `contexts.json` — e.g. `~/Github-Acme/**` → `acme`.
6. **`default`** in `contexts.json` — fallback.

The "ancestor" walk goes up to `$HOME` and stops there, never above.

## How skills use this

Every skill that needs API tokens does:

```bash
set -a; source "$(ro context env)"; set +a
```

`$(ro context env)` returns the absolute path of the env file the resolver picked. For single-context users that's always `~/.claude/.env.personal`; for multi-context users it varies per cwd.

Backwards compat: `~/.claude/.env` is still a symlink to whichever context was last `ro context use`'d. Skills that haven't migrated to `$(ro context env)` keep working unchanged.

## State layout

Everything under `~/.claude/` (no split with `~/.config/`):

```
~/.claude/
  contexts.json         # { default, active, rules: [[glob, name], ...] }
  .env                  # symlink, kept for backwards compat
  .env.personal         # real file per context (mode 600)
  .env.<other>          # one per profile
```

## Onboarding a new context

```bash
# 1. Copy the personal template as a starting point
cp ~/.claude/.env.personal ~/.claude/.env.acme
chmod 600 ~/.claude/.env.acme
# …edit with the client's credentials…

# 2. Pin a repo to its context (preferred — committed, no global config needed)
echo acme > /path/to/acme/repo/.ro-context

# OR add a cwd-glob auto-rule
ro context add-rule '~/Github-Acme/**' acme
```

## Failure modes the design handles

| If you… | Resolution |
|---|---|
| Forget to switch context, open a terminal in a Simplicity repo | `.ro-context` resolves automatically |
| Clone a new repo from a client without thinking | cwd-glob (`~/Github-<Client>/**`) catches it |
| Have overlapping repos in `~/Dev/` (work + personal side-by-side) | Each repo's own `.ro-context` wins over the glob |
| Want to test cross-account scripts | `RO_CONTEXT=other-account` env var for one shell |
| Want to "stay in" one context for a long-running session | `ro context use <name>` until `ro context auto` |
| Have a long-running process (dev server, Claude session) | The process holds whatever it was started with — symlink swap doesn't poke it. Restart needed |

## See also

- `[[ro-context-env-profiles]]` (LLM wiki research vault) — the design rationale + pull-out checklist
- `~/.claude/contexts.json` — the user's actual rules + default
- `scripts/ro` (this skill) — the implementation, ~320 lines of bash, zero dependencies beyond bash + jq + awk + sed
