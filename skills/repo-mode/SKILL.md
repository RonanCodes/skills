---
name: repo-mode
description: Resolve, set, or check whether the current repo is in `personal` mode (PRDs and slices publish as GitHub issues) or `work` mode (everything stays local in gitignored .ralph/ files, nothing posted to the GH backlog). Auto-prompted on first use by /ro:write-a-prd, /ro:slice-into-issues, /ro:ralph, /ro:planner-worker, and /agentic-e2e-flow. Invoke directly to inspect or override the mode (e.g. `/ro:repo-mode work`, `/ro:repo-mode personal --global`, `/ro:repo-mode --check`). Use when the user wants to flip a repo between personal and work mode, set a global default, or asks why a skill is creating GH issues (or not).
category: workflow
argument-hint: [personal | work] [--global] [--check] [--clear]
allowed-tools: Bash Read Write Edit AskUserQuestion
---

# Repo Mode

Some of Ronan's repos are personal (his own GitHub, agent-native, GH issues are the backlog). Others are work (a separate Atlassian / Jira / Azure DevOps / employer GH project owns the backlog) and the agent flow needs to stay invisible — no GH issues created, everything in gitignored local files.

This skill is the canonical control point. The five swarm-pipeline skills (`write-a-prd`, `slice-into-issues`, `ralph`, `planner-worker`, `agentic-e2e-flow`) all defer to the resolution algorithm below before deciding their default `--target` / `--source`.

## Modes

- **`personal`** — PRDs and slices publish as GitHub issues. `ralph` and `planner-worker` consume from `gh issue list --label ready-for-agent`. The agent-native Pocock pattern. Default for repos owned by `RonanCodes` or `Simplicity-Labs`.
- **`work`** — Nothing leaks to GitHub. PRDs go to `.ralph/<name>/prd.md`. Slices go to `.ralph/<name>/issues/*.md`. `ralph --kanban` and `planner-worker` consume from disk. `.ralph/` is auto-added to `.gitignore`. The flow is fully invisible to the work GH/Jira/ADO project.

## Resolution algorithm (the contract)

Any skill that needs to know the mode runs this exact sequence:

```bash
# 1. Per-repo override (highest precedence)
mode=""
[ -f .claude/repo-mode ] && mode="$(tr -d '[:space:]' < .claude/repo-mode)"

# 2. Global default
[ -z "$mode" ] && [ -f "$HOME/.claude/repo-mode" ] && mode="$(tr -d '[:space:]' < "$HOME/.claude/repo-mode")"

# 3. Validate
case "$mode" in personal|work) ;; *) mode="unset" ;; esac

echo "$mode"
```

If `mode == unset`, the calling skill MUST prompt the user once via `AskUserQuestion`, persist the answer (see "First-run prompt" below), then proceed. After persisting, the same algorithm returns the saved value on every subsequent call so the prompt fires exactly once per repo.

## First-run prompt (what calling skills do when mode is unset)

1. Get the suggested default by inspecting the gh remote owner:

   ```bash
   owner="$(gh repo view --json owner -q .owner.login 2>/dev/null || true)"
   case "$owner" in
     RonanCodes|Simplicity-Labs) suggested=personal ;;
     "") suggested=personal ;;   # no gh remote at all → personal default (legacy local flow)
     *) suggested=work ;;
   esac
   ```

2. Ask via `AskUserQuestion` (header: "Repo mode"):

   > "How should this repo be treated for agent-driven PRD / slice / Ralph flows?"
   >
   > Options (recommended option listed first):
   > - **Personal — publish PRDs and slices as GitHub issues** (the agent-native Pocock pattern; this is the gh-remote-owner suggestion when owner ∈ {RonanCodes, Simplicity-Labs})
   > - **Work — keep everything local and gitignored** (nothing leaks to the work GH/Jira/ADO project; PRDs go to `.ralph/<name>/prd.md`, slices to `.ralph/<name>/issues/*.md`)

3. Save the answer to `.claude/repo-mode` (per-repo, always):

   ```bash
   mkdir -p .claude
   printf '%s\n' "$answer" > .claude/repo-mode
   ```

4. Add `.claude/repo-mode` to `.gitignore` if not already present (so the choice doesn't leak into work repos):

   ```bash
   touch .gitignore
   grep -qxF '.claude/repo-mode' .gitignore || printf '\n# repo-mode (personal/work agent flow toggle)\n.claude/repo-mode\n' >> .gitignore
   ```

5. If mode == `work`, also ensure `.ralph/` is gitignored:

   ```bash
   grep -qxF '.ralph/' .gitignore || printf '\n# Ralph local backlog (work-mode private)\n.ralph/\n' >> .gitignore
   ```

6. Ask one follow-up via `AskUserQuestion` (header: "Global default"):

   > "Save `<answer>` as your global default for new repos too? (writes to `~/.claude/repo-mode`)"
   >
   > - **Yes** — most of your repos are this kind, save it as the default
   > - **No** — only set for this repo, prompt me again next time

   If yes:

   ```bash
   mkdir -p "$HOME/.claude"
   printf '%s\n' "$answer" > "$HOME/.claude/repo-mode"
   ```

7. Echo the resolution back to the user in one sentence: `Repo mode set to <answer> (saved to .claude/repo-mode<, global default updated>).`

## Direct invocation

```
/ro:repo-mode                    # --check is implicit; print current mode + where it came from
/ro:repo-mode --check            # explicit check
/ro:repo-mode personal           # set per-repo to personal (writes .claude/repo-mode)
/ro:repo-mode work               # set per-repo to work (writes .claude/repo-mode + adds .ralph/ to .gitignore)
/ro:repo-mode personal --global  # set global default to personal (writes ~/.claude/repo-mode)
/ro:repo-mode work --global      # set global default to work
/ro:repo-mode --clear            # remove per-repo override; fall back to global default
/ro:repo-mode --clear --global   # remove global default
```

When the first positional arg is `personal` or `work`, write to `.claude/repo-mode` (or `~/.claude/repo-mode` with `--global`). When `work` is set per-repo, also append `.ralph/` to `.gitignore` if missing.

When `--check` (or no arg), run the resolution algorithm and print:

```
Repo mode: <personal|work|unset>
Source:    <per-repo .claude/repo-mode | global ~/.claude/repo-mode | unset>
GH owner:  <owner>  (suggested: <personal|work>)
```

If `unset`, also print: `No mode set yet. Next swarm-pipeline skill (write-a-prd, slice-into-issues, ralph, planner-worker, agentic-e2e-flow) will prompt you once and persist.`

## Why this exists

Without it, every PRD interview ended with "publish as GH issue?" and the user had to remember per-repo to say no for work repos. One leaked issue on a work GH project is a real awkward conversation. This makes "stay invisible at work" a one-time decision per repo (or one global decision) instead of a per-invocation cognitive load.

## Cross-references

- agent-native repo Pocock pattern → `[skill-lab:agent-native-repo-pocock](obsidian://open?vault=llm-wiki-skill-lab&file=wiki%2Fpatterns%2Fagent-native-repo-pocock)`
- Calling skills that defer to this: `/ro:write-a-prd`, `/ro:slice-into-issues`, `/ro:ralph`, `/ro:planner-worker`, `/agentic-e2e-flow`
