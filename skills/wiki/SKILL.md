---
name: wiki
description: Capture findings, decisions, and research from the current project into the LLM Wiki repo. Routes to the wiki repo's own ingest skills (ingest-session, ingest-text, rough-notes) by reading their SKILL.md as the spec, so behaviour stays in sync with the wiki's conventions. Per-project config in .ronan-skills-llm-wiki.local.json maps the current project to one or more vaults. Use when the user says "update the wiki", "add this to the wiki", "capture our findings", or wants to ingest research from outside the wiki repo.
category: research
argument-hint: <(no args = ingest current session) | text [<file-or-->] | notes | status | config | vaults>
allowed-tools: AskUserQuestion, Read, Write, Edit, Bash(ls *), Bash(mkdir *), Bash(date *), Bash(git log *), Bash(git -C *), Bash(cat *), Bash(test *), Glob, Grep
---

# Wiki

Bridge skill: lets any project push findings into the LLM Wiki repo at `~/Dev/ai-projects/llm-wiki` without leaving the current working directory.

It does **not** reimplement the wiki's ingest logic. Instead, it reads the wiki repo's own `SKILL.md` files (`ingest-session`, `ingest-text`, `rough-notes`) and follows their instructions verbatim against the resolved target vault. The wiki's skills stay the single source of truth; this skill just resolves the vault and proxies.

## Why this skill exists

The wiki's ingest skills live in `~/Dev/ai-projects/llm-wiki/.claude/skills/` as project-local skills. They are not visible from any other project's session. Without this bridge, a user doing research in Project A has to either:

1. `cd` into the wiki repo and re-explain the context, or
2. Re-author the ingest logic in Project A's tooling.

This skill picks option 3: load the wiki's SKILL.md as the playbook, execute the steps, write to the right vault.

## Usage

```
/ro:wiki                              # ingest current session into default vault (follows ingest-session)
/ro:wiki --vault <vault-short>        # specific vault, e.g. --vault ai-research
/ro:wiki --title <slug>               # override title slug
/ro:wiki text                         # ingest pasted/explicit text (follows ingest-text)
/ro:wiki text path/to/notes.md        # ingest a local markdown file
/ro:wiki notes                        # drop to scratchpad/ for later /rough-notes cleanup
/ro:wiki status                       # show config, default vault, last 3 entries
/ro:wiki config                       # initialise or edit .ronan-skills-llm-wiki.local.json
/ro:wiki vaults                       # list all vaults available in the wiki repo
```

`<vault-short>` is the vault name without the `llm-wiki-` prefix (e.g. `ai-research`, `side-projects`). The skill resolves the full directory name internally.

## Step 0: Resolve the wiki repo and config

1. **Wiki repo path**: default `~/Dev/ai-projects/llm-wiki`. If absent, error and ask the user where the wiki lives. Save the answer into the per-project config.
2. **Per-project config**: read `./.ronan-skills-llm-wiki.local.json` from the current working directory.
   - If missing, run the **config init** flow (Step 1).
   - If present, parse it and proceed.

### Config file shape

```json
{
  "wiki_repo_path": "/Users/ronan/Dev/ai-projects/llm-wiki",
  "project_name": "ronan-skills",
  "default_vault": "side-projects",
  "vaults": ["side-projects", "skill-lab"],
  "notes": "Optional: why these vaults are the target for this project"
}
```

- `default_vault` and entries in `vaults` use the **short form** (no `llm-wiki-` prefix).
- The file should be added to `.gitignore` if the project is a git repo (skill warns the user once if it isn't).

## Step 1: Config init flow

Triggered when `./.ronan-skills-llm-wiki.local.json` is missing, or when user runs `/ro:wiki config`.

1. List the available vaults: `ls <wiki_repo_path>/vaults/` and strip the `llm-wiki-` prefix.
2. Use `AskUserQuestion` to ask:
   - **Which vault(s) should this project write to by default?** (multi-select from the vault list)
   - **Of those, which is the primary default?** (single-select, only if more than one was picked)
3. Write the config file to `./.ronan-skills-llm-wiki.local.json` with `project_name` set to the current directory's basename.
4. If the project is a git repo (`test -d .git`), check whether `.gitignore` already excludes `*.local.json` or the file specifically. If not, append `.ronan-skills-llm-wiki.local.json` to `.gitignore`. Tell the user.
5. Print a one-line confirmation: which vault(s) are configured, what the file path is.

## Step 2: Resolve the target vault for this invocation

Order of precedence:

1. `--vault <short>` flag passed on the command line.
2. If user said something like "the X vault" or "into ai-research" in their prompt, parse that out.
3. `default_vault` from the config.
4. If config has only one entry in `vaults`, use it.
5. If still ambiguous, ask the user via `AskUserQuestion` with the configured vaults as options.

The full vault directory is `<wiki_repo_path>/vaults/llm-wiki-<short>/`.

Verify the directory exists. If not, error with the list of actual vault directory names.

## Step 3: Pick the wiki skill to follow

Based on the subcommand:

| Subcommand | Wiki skill to follow | SKILL.md path |
|---|---|---|
| (default, no subcommand) | `ingest-session` | `<wiki>/.claude/skills/ingest-session/SKILL.md` |
| `text` | `ingest-text` | `<wiki>/.claude/skills/ingest-text/SKILL.md` |
| `notes` | `rough-notes` (cleanup mode) | `<wiki>/.claude/skills/rough-notes/SKILL.md` |

## Step 4: Read and execute the wiki skill

1. **Read** the chosen SKILL.md in full. Treat it as the authoritative playbook.
2. Substitute the resolved vault into any `<vault>` placeholder in its instructions.
3. **Execute every step** the wiki skill describes — vault paths, frontmatter, index/log updates, ROADMAP updates, commits, etc. — exactly as written.
4. **Do not skip steps** to be terse. The wiki skill's commit + index + log + ROADMAP updates are load-bearing for searchability later.
5. If the wiki skill says "auto-commit", honour it. Run the commit inside the wiki repo (`git -C <wiki_repo_path> ...`), respecting `~/CLAUDE.md` rules: emoji + conventional format, no Co-Authored-By, weekday-hours timestamp rule.

## Step 5: Report back to the calling project

After the wiki skill's own report, add a one-line tail in the calling project:

- Path to the new file (absolute, so the user can open it)
- Vault short-name
- The commit SHA inside the wiki repo

Example:
```
Wrote: ~/Dev/ai-projects/llm-wiki/vaults/llm-wiki-side-projects/wiki/sources/session-notes-2026-04-28-wiki-bridge.md
Vault: side-projects | Commit: 7a3b2c9 (in wiki repo)
```

## Subcommand: status

```
/ro:wiki status
```

1. Read config. If missing, suggest `/ro:wiki config`.
2. Print: project name, configured vaults, default vault, wiki repo path.
3. List the 3 most recent files under `<wiki>/vaults/llm-wiki-<default>/wiki/sources/` by mtime.
4. Print the last commit in the wiki repo: `git -C <wiki> log -1 --oneline`.

## Subcommand: vaults

```
/ro:wiki vaults
```

`ls <wiki_repo_path>/vaults/` and print short-form names with a one-line description from each vault's `wiki/index.md` first heading (read line 1 of each).

## Cross-project skill access — note for future maintainers

Skills are scoped to: `~/.claude/skills/`, plugins, and the **current project's** `.claude/skills/`. The wiki repo's project-local skills are **not** invocable from other projects via the `Skill` tool.

This skill works around that by **reading the wiki's SKILL.md files directly with the `Read` tool** and executing their instructions inline. That keeps the wiki skills as the single source of truth without requiring them to be promoted to global `ro:*` skills.

If the wiki ever moves its skills to a new path, update the paths in Step 3.

## Rules

- The new skill never modifies wiki repo files outside the configured vault and the standard index/log/ROADMAP files described in `ingest-session`.
- Commits inside the wiki repo follow `~/CLAUDE.md`: emoji + conventional commit, no Co-Authored-By, weekday-hours timestamp guard (08:30–18:00 forbidden Mon–Fri).
- The `.ronan-skills-llm-wiki.local.json` file is **per-project, gitignored**. Never commit it.
- If the user asks to write to a vault not in their config, do it but ask whether to add the vault to the config for next time.
- Apply `/ro:write-copy` rules to every line of generated wiki content. No em-dashes, no AI-tell vocabulary, no rhetorical-reversal filler.
- This skill is a thin router: when in doubt about *how* to format a wiki entry, the wiki's own SKILL.md wins.

## Examples

**Capture findings from a research session in Project A:**

```
[user, working in ~/Dev/some-project]
> we've been figuring out the right vector store for this app for the last hour, can you update the wiki?

[Claude]
/ro:wiki
→ reads ./.ronan-skills-llm-wiki.local.json (default_vault = ai-research)
→ reads ~/Dev/ai-projects/llm-wiki/.claude/skills/ingest-session/SKILL.md
→ follows its 8 steps targeting llm-wiki-ai-research
→ writes session-notes-2026-04-28-vector-store-pick.md, updates index/log/ROADMAP, commits
→ reports the path + commit SHA
```

**First-time setup in a new project:**

```
> add our findings to the wiki

[Claude]
→ no .ronan-skills-llm-wiki.local.json found
→ runs config init: lists vaults, asks user to pick
→ writes config, adds to .gitignore
→ proceeds with the ingest
```

**Ingest a specific markdown file the user already wrote:**

```
> can you push docs/architecture-notes.md into the side-projects vault?

[Claude]
/ro:wiki text docs/architecture-notes.md --vault side-projects
→ follows ingest-text against llm-wiki-side-projects
```
