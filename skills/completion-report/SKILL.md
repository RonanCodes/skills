---
name: completion-report
description: Render a browsable HTML completion report at the tail of any autonomous coding run (Ralph, planner-worker, agentic-e2e-flow) or on demand for any git range. Shows per-story / per-PR cards with CI status, file-change stats, unified diffs, and a per-file rollback command. Inspired by ruizrica/agent-pi's completion-report extension. Fires automatically before Pushover when invoked from Ralph or planner-worker (the ping links to the report). Manual trigger via /ro:completion-report. Writes to .completion-reports/<timestamp>-<slug>.html in the current repo (gitignored). Triggers on "completion report", "what changed in this run", "show me the diff report", "build the completion report", "/ro:completion-report".
category: workflow
argument-hint: [--range <gitref>..<gitref>] [--since <duration>] [--prs <n1,n2,...>] [--prd <name>] [--title <text>] [--open|--no-open] [--out <path>] [--no-ping]
allowed-tools: Bash Read Write Edit Glob Grep
---

# Completion Report

End-of-run artifact that answers four questions in one browser tab:

1. **What ran?** Branch, base, duration, PR/story count, pass/fail mix.
2. **What changed?** Per-PR cards with file stats, summary, CI status, mergeability.
3. **What's the actual diff?** Per-file unified diff, syntax-highlighted, collapsible.
4. **How do I undo any piece of it?** Per-file rollback command, per-PR revert command, copy-button on each.

It's a single self-contained HTML file. No backend, no build step. Open it with `open` and read it in the browser. The HTML is also valid for emailing or sharing.

The shape is lifted from `ruizrica/agent-pi`'s `completion-report` extension (see `[ai-research:agent-pi]`). The novelty for our flow is making it the **tail call** of every autonomous coding run, so the Pushover ping carries the report path as a deep link.

## When to fire

**Automatic** (the load-bearing case):

- End of any `/ro:ralph` run against a real backlog (NOT `--plan-only`, NOT one-shot `--mode single` exploration). Fires BEFORE `/ro:pushover` so the ping message can include the report path.
- End of any `/ro:planner-worker` run against a real backlog (NOT `--plan-only`). Same Pushover-precedes ordering.
- End of any `/agentic-e2e-flow` run that reached the ralph-or-planner-worker phase.

The autonomous skills call this skill explicitly. Don't invoke it from inside an autonomous-loop body — only at the tail.

**Manual**:

- User says "completion report", "show me what changed", "build the diff report", "what did the swarm ship", or invokes `/ro:completion-report`.
- After a heavy hand-rolled session when you want a single shareable artifact (commit a range, copy the report path into Slack / a PR description / a daily log).

**Do NOT fire**:

- Mid-loop progress checks (use `git status` / `gh pr list` — those are cheap and don't need rendering).
- Inside an active Ralph iteration (the loop body has its own per-story progress.txt).
- Sessions with zero commits or zero PRs touched (nothing to report — the skill is a no-op and will tell the user).

## Output location

Per repo, gitignored:

```
<repo-root>/.completion-reports/<YYYY-MM-DDTHH-MM>-<slug>.html
```

On first invocation in a repo, append `.completion-reports/` to `.gitignore` (idempotent — check first). The slug comes from `--title` (kebab-cased) or, in autonomous mode, the PRD name (`--prd <name>`).

After writing, print the absolute path. If `--open` (default unless the parent skill passes `--no-open`), launch with `open` (macOS). The user wants `open`, not `afplay`-style direct playback, per memory `feedback_open_audio_files.md` — same principle applies here: GUI surface, not raw process.

## Range resolution

The skill needs a **commit range** and a **PR set**. Pick whichever the caller supplied; otherwise auto-detect.

Priority order:

1. `--prs n1,n2,n3` — explicit PR set. Resolves range from each PR's `baseRefOid..headRefOid`. Best when the caller (Ralph / planner-worker) already knows which PRs it shipped.
2. `--range <a>..<b>` — explicit git range. Use as-is; no PR cards (only commit cards).
3. `--since <duration>` (e.g. `4h`, `1d`) — `git log --since=<duration> --pretty=%H`. No PR cards unless `gh pr list --state merged --search "closed:>=<computed-date>"` returns matches.
4. `--prd <name>` — read `.ralph/<name>.progress.txt`, extract every `PR: #<n>` line, treat as `--prs`.
5. **Default** (no flag): `git merge-base HEAD origin/main`..`HEAD`, PR set = `gh pr list --author @me --state merged --search "closed:>=$(date -u -v-1d +%Y-%m-%d)"` if `gh` available, otherwise empty.

If the resolved range is empty (zero commits), exit early with a one-line summary: `no commits in range, nothing to report`. Do NOT write an empty HTML file.

## Report structure

```
┌────────────────────────────────────────────────────────────────┐
│ <title>                                                        │
│ <repo> @ <branch> · started <ts> · finished <ts> · <duration>  │
│ <N> PRs · <M> commits · <added>+/<removed>- lines · <files>    │
│                                                                │
│ Risk panel — flags only show if triggered:                     │
│   ⚠ schema migration touched (drizzle/, migrations/)            │
│   ⚠ env or secret changes (.env*, wrangler.toml secrets)       │
│   ⚠ deletions > 100 lines in one PR                             │
│   ⚠ lockfile-only PRs                                           │
└────────────────────────────────────────────────────────────────┘

┌─ PR #61 · ✅ merged · ✅ CI green · planner ────────────────────┐
│ Title: "feat(onboarding): add email-verification step"          │
│ Author: claude (Ralph) · Squash: 8240af6                        │
│ Files: 6 changed · +142 / -8                                    │
│ Summary: <if available from PRD/progress.txt>                   │
│                                                                 │
│ Files (click to expand diff):                                   │
│   ▸ src/auth/verify.ts             +88 / -0   [revert this file]│
│   ▸ src/auth/verify.test.ts        +42 / -0   [revert this file]│
│   ▸ db/schema.ts                   +6  / -2   [revert this file]│
│   ...                                                           │
│                                                                 │
│ Rollback this PR: git revert -m 1 8240af6                       │
└─────────────────────────────────────────────────────────────────┘

(repeat per PR / per orphan commit)
```

Each `[revert this file]` button is a one-liner clipboard copy:

```bash
git checkout <sha-before-pr>~1 -- <file>
```

The HTML uses `<details>`/`<summary>` for collapsible diffs, no JS framework. Syntax highlighting via inline `<pre>` with CSS classes (highlight.js loaded from a vendored copy in the skill's `assets/`).

## Inputs the skill consumes

| Source | Use |
|---|---|
| `git log <range>` | commit list, commit messages, timestamps |
| `git diff <range>` per file | unified diff bodies |
| `git diff --stat <range>` | per-file change stats |
| `gh pr view <n> --json title,number,state,mergeable,statusCheckRollup,author,baseRefOid,headRefOid,mergedAt,body` | PR card data |
| `gh pr diff <n>` | optional fallback when range diff is messy |
| `.ralph/<prd>.progress.txt` | story timestamps, duration, learnings (when `--prd` supplied) |
| `.ralph/<prd>.session.md` | session-level duration |

## Risk-panel triggers

Surface a top-of-page warning when ANY of these match a PR or commit in range. The risks are deterministic — no LLM judgement, just file-path and stat checks:

- **Schema migration touched**: any path matching `**/migrations/**`, `**/drizzle/**.sql`, `**/prisma/migrations/**`, or commit message starting with `🗄️`/`migration:` per the repo's emoji map.
- **Env / secrets**: any path matching `.env*`, `wrangler.toml` with a `[[secrets]]` block change, `**/secrets.toml`, or commit message containing `secret`/`token`/`key:`.
- **Large deletions**: any PR with > 100 lines removed in a single file.
- **Lockfile-only PR**: a PR whose only changed files are `package-lock.json`, `pnpm-lock.yaml`, `bun.lockb`, `yarn.lock`, or `Cargo.lock`.
- **No tests in a feat PR**: PR title starts with `✨ feat:` and no path matches `**/*.test.*` / `**/*.spec.*` / `tests/**`.

These are warnings, not blockers — the user reads the report after the run, the gate is the merger / reviewer.

## Integration with `/ro:pushover`

The autonomous-skill callers (Ralph, planner-worker, agentic-e2e-flow) drive this ordering:

1. Run finishes (clean or failed).
2. Caller invokes `/ro:completion-report` with `--prd <name>` (or `--prs <list>`) and `--no-open` (we don't want to pop a browser on a remote / SSH session).
3. Skill writes the HTML, prints the absolute path.
4. Caller invokes `/ro:pushover` with a `--url file://<absolute-path>` so the ping deep-links to the report.

Pushover message anatomy stays the same (state + concrete metric + next step) — the URL is supplementary, not a replacement for the message text.

If the report isn't useful (zero commits, range empty), the caller skips both the report and the URL but STILL sends the Pushover ping with state.

## Manual usage

```bash
# After a heavy hand-rolled session, no flags — defaults to "since I branched from origin/main"
/ro:completion-report

# Specific PR set (e.g. cherry-picked, or PRs you reviewed today)
/ro:completion-report --prs 61,62,64 --title "auth slice — 3 PRs"

# A named PRD, after Ralph
/ro:completion-report --prd phase-2-onboarding-2026-05-06

# Custom git range, custom title
/ro:completion-report --range origin/main..HEAD --title "feature-x review"

# Don't open the browser (useful in scripts and over SSH)
/ro:completion-report --no-open
```

## Implementation outline

The skill is a single bash + heredoc that:

1. Parses flags.
2. Resolves range + PR set per the priority order above.
3. Ensures `.completion-reports/` is gitignored (idempotent).
4. Generates the HTML via a single `cat <<'EOF' > <path>` heredoc that interpolates pre-computed sections. No template engine.
5. Echoes the absolute path to stdout (so callers can capture it).
6. Opens the file unless `--no-open`.

Three scripts under `scripts/`:

- `scripts/generate.sh` — main entrypoint, orchestrates the steps above.
- `scripts/risk-checks.sh` — runs each risk-panel trigger against the resolved range, prints triggered ones as `key:value` lines.
- `scripts/diff-to-html.sh` — wraps `git diff` per file into a syntax-highlighted `<pre>` block. Uses `pygmentize` if available; falls back to plain `<pre>`.

Bash, not Node — keeps the skill dependency-free for any repo.

## Notes for future iterations

- A second render mode (markdown) is tempting (per `feedback_artifact_format_mix.md`) but defer until a real "I want to paste this into a PR description" moment surfaces. HTML wins for diffs + collapsible sections; markdown wins for inline pasting. If both end up needed, expose a `--format html|md` flag and reuse the same risk + range resolution.
- Don't try to embed Mermaid diagrams of the PR DAG. The DAG is visible from `git log --graph` and adding Mermaid drags in a renderer dependency. The HTML report is a *list* of changes, not a diagram of them.
- The skill's HTML must work offline. Vendor highlight.js into `assets/highlight.min.js`; do NOT load from a CDN. Bandwidth and offline-on-plane reasons.

## Sources

- Pattern lifted from `ruizrica/agent-pi`'s `completion-report` extension. See [ai-research:agent-pi](obsidian://open?vault=llm-wiki-ai-research&file=wiki%2Fentities%2Fagent-pi) and the article [ai-research:agent-pi-medium-ruiz](obsidian://open?vault=llm-wiki-ai-research&file=wiki%2Fsources%2Fagent-pi-medium-ruiz).
- Sibling skills: `/ro:ralph`, `/ro:planner-worker`, `/ro:pushover`, `/ro:close-session`.
