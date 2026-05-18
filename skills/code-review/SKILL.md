---
name: code-review
description: CodeRabbit-style PR review. Reads a GitHub PR, produces a walkthrough plus inline findings tagged by severity (critical / major / minor / question / praise) in a kind-but-direct voice. Default mode writes a local markdown report under `.code-review/`; `--post` publishes the review to GitHub as RoBot-branded inline comments via one atomic API call. Use when user wants to review a PR, run a code review, give feedback on a teammate's branch, or get a second-opinion review before merging. Triggers on "review this PR", "review PR #N", "review skip's PR", "code-review", "robot review".
category: development
argument-hint: [<pr-number-or-url>] [--post] [--local] [--poem] [--assertive] [--repo owner/name] [--profile chill|standard|strict]
allowed-tools: Bash(gh *), Bash(git *), Bash(jq *), Bash(cat *), Bash(mkdir *), Bash(test *), Bash(grep *), Read, Write, Edit, AskUserQuestion
---

# Code Review

CodeRabbit-style PR reviewer with two output modes: local markdown report (default) or GitHub review with inline comments (with `--post`). Every public comment is prefixed `**🤖 RoBot review**` so it's obvious the source is automation.

Spec: [[coderabbit-style-pr-review]] in `llm-wiki-skill-lab/wiki/patterns/`. Read `reference.md` next to this SKILL.md for the full severity taxonomy, comment templates, anti-patterns, and `gh api` JSON shapes.

## Usage

```
/ro:code-review                          # interactive: picks open PR for current repo
/ro:code-review 171                      # review PR #171 in current repo, local report only
/ro:code-review 171 --post               # local report AND post to GitHub
/ro:code-review --post-only 171          # post to GitHub, skip local report
/ro:code-review owner/repo#171           # cross-repo
/ro:code-review https://github.com/...   # paste a PR URL
/ro:code-review 171 --poem               # include a poem in the walkthrough (default off)
/ro:code-review 171 --assertive          # include minor/nitpick findings (default: critical + major + question only)
/ro:code-review 171 --profile strict     # strict = REQUEST_CHANGES even for major; chill = APPROVE if no critical
/ro:code-review 171 --worktree           # check the PR out in a sibling git worktree so it can run side-by-side with main
/ro:code-review --worktree-cleanup 171   # remove the worktree after review
```

## When to use

- A teammate has opened a PR and you want a structured review before merge.
- You want a second opinion on your own PR.
- You want a local-only report (private feedback, draft thinking, or the PR isn't on GitHub).

## When NOT to use

- The PR is enormous (>2000 LOC changed): split or ask the author to. This skill caps reviewable diff.
- The PR is still draft AND in flux: review will go stale within the hour.
- The repo has its own CodeRabbit / human review already running and adding RoBot would be noise.

## Output modes

| Mode | Trigger | What happens |
|------|---------|--------------|
| **local** (default) | no flag | Writes `./.code-review/PR-<n>-<slug>.md`. Nothing touches GitHub. |
| **post** | `--post` | Writes the local report AND posts to GitHub. |
| **post-only** | `--post-only` | Posts to GitHub. No local report. |

Always default to local. The user must opt in to GitHub. Confirm before posting if you got here through `/ro:code-review <N> --post` without seeing the report first.

## Process

### 1. Resolve PR

```bash
# If argument is a number, use current repo
gh pr view <N> --json number,title,body,author,headRefName,headRefOid,baseRefName,changedFiles,additions,deletions,url,state,isDraft

# If URL, parse owner/repo/number from it
# If --repo passed, use that

PR_HEAD_SHA=$(gh pr view <N> --json headRefOid -q .headRefOid)
PR_URL=$(gh pr view <N> --json url -q .url)
```

Refuse if `state != OPEN` (unless `--allow-closed`). Warn if `isDraft = true`.

### 2. Pull diff + per-file context

```bash
# Full unified diff (for finding lines)
gh pr diff <N> > /tmp/pr-<N>.diff

# Changed files for per-file review
gh pr view <N> --json files -q '.files[].path' > /tmp/pr-<N>.files
```

If the diff exceeds ~80k tokens, summarise per-file and warn that depth will be lower.

### 3. Check out the branch locally (read-only)

Two strategies depending on whether you want side-by-side dev:

**Default — checkout in place:**

```bash
gh pr checkout <N>  # fetches and switches to the branch
# After review:
git checkout -    # back to whatever the user was on
```

This lets you `Read` files at the PR head for context beyond the diff hunks. Fast and ephemeral. Don't run tests or builds; only read.

**With `--worktree` — reusable sibling worktree:**

Use the helper script — it handles worktree creation, `.dev.vars` copy, dependency install, and D1 migration apply in one shot. It is REUSABLE: one worktree directory called `<repo>-code-review` that you switch between PRs as you review them.

```bash
# First time / new PR (creates worktree if missing, switches it if present)
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh 171

# Switch the same worktree to a different PR (no fresh pnpm install)
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh --switch 195

# Status / cleanup
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh --status
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh --cleanup
```

Per-worktree state that's automatically isolated by cwd: `.wrangler/state/` (local D1 SQLite, KV, R2), `node_modules/`, `.dev.vars`, `.code-review/`. State that is shared (which is the point of worktrees): `.git/objects/`, git config, remote refs.

See `WORKTREE.md` next to this SKILL.md for the full side-by-side recipe + troubleshooting.

When to use `--worktree`:
- The user wants to run the PR's dev server side-by-side with the main checkout for visual comparison.
- The PR includes migrations or schema changes you'd rather not apply to the main checkout's local DB.
- You need to keep working on main while the PR sits half-reviewed.

## Side-by-side dev (worktree mode)

When the user wants to run BOTH apps simultaneously (e.g., for visual diffing the PR against main):

| Concern | Default | What to do |
|---------|---------|------------|
| **Port** | Most stacks hardcode `--port 3000` in `dev` script | Override on the PR worktree: `pnpm dev -- --port 3001` or `npx vite dev --port 3001` |
| **D1 / local SQLite** | `.wrangler/state/v3/d1/<id>.sqlite` lives per cwd | Naturally isolated by worktree. Run migrations once per worktree. |
| **KV / R2 (Cloudflare)** | Same as D1 — per cwd in `.wrangler/state/` | Naturally isolated. |
| **`.dev.vars` / `.env`** | Gitignored, won't follow the worktree | Copy from main worktree once. Edit if any value is port-specific. |
| **Clerk auth callbacks** | Dev keys whitelist exact redirect URIs | Add the second port (e.g., `http://localhost:3001`) to Clerk's allowed origins/redirect URLs once; both ports then work simultaneously. |
| **External webhooks** (Stripe, Resend, Nango) | Tunnels resolve to one URL | Only one worktree can claim the public webhook URL at a time. Not a blocker for visual review or static-flow testing. |
| **Third-party APIs in mutate mode** | Shared upstream | Read-only inspection is fine. Both worktrees writing to the same upstream (e.g., Shopify dev store, Nango sandbox) can race. Use the PR worktree for read-only flows during comparison. |
| **Browser** | One profile = one cookie jar | Open the PR worktree in an incognito window or a separate Chrome profile if the auth cookies collide. |

Quick recipe:

```bash
# Terminal 1 (main checkout)
cd ~/Dev/projects/<repo>
pnpm dev                          # runs on :3000

# Terminal 2 (PR worktree)
cd ~/Dev/projects/<repo>-pr-<N>
pnpm dev -- --port 3001           # runs on :3001
```

Both Cloudflare-Workers / TanStack-Start / Vite apps can run at once. The thing that breaks is anything that wants exclusive global state: a single webhook tunnel URL, a single browser cookie for the same domain, or an external sandbox in write mode.

If the user is mainly screenshotting and comparing layouts, the side-by-side setup is genuinely free. If they need full mutation flows, pick one worktree at a time.

### 4. Read for correctness FIRST

In this order:
1. **Bugs** — null/undefined, off-by-one, race conditions, error paths, unchecked casts.
2. **Security** — injection, XSS, secret leakage, auth bypass, CSRF, unsafe deserialization.
3. **Contract / regression** — public API changes, breaking imports, schema migrations.
4. **Design** — architecture concerns, abstractions, dependencies.
5. **Tests** — coverage of new code, missing edge cases.
6. **Style / nits** — only if `--assertive`.

Skip anything a linter handles (formatting, import order, missing semicolons).

### 5. Classify each finding

Use the 5-level taxonomy (full table in `reference.md`):

| Level | Emoji | When | GH event implication |
|-------|-------|------|----------------------|
| **critical** | ⚠️ | Bug, security, broken contract. Must fix before merge. | Triggers `REQUEST_CHANGES` |
| **major** | 🛠️ | Real design/quality concern. Address or push back. | `COMMENT` (or `REQUEST_CHANGES` with `--profile strict`) |
| **minor** | 🧹 | Polish, naming. Author may ignore. | `COMMENT`. Suppressed unless `--assertive`. |
| **question** | ❓ | "Is this intentional?" — clarification. | `COMMENT` |
| **praise** | ✨ | Sincere recognition. Sparingly. | `COMMENT` |

Cap on nitpicks per review: **5**. Drop the rest.

### 6. Write the walkthrough

Markdown. Always include these sections, in this order:

```
**🤖 RoBot review** — kind, direct, opinionated.

## Walkthrough
<one paragraph: intent of the PR, not file enumeration>

## Changes
| File | Change |
|------|--------|
| ... | ... |

## Estimated review effort
<1-5> / 5

## Findings
- 🔴 Critical: <N>
- 🟠 Major: <N>
- 🟡 Minor: <N> (suppressed; use --assertive to surface)
- 🔵 Questions: <N>
- 🟢 Praise: <N>

## Sequence diagram
<mermaid, only when the PR touches multi-component interactions>

## Out of scope
<observations the reviewer noticed but didn't flag inline because they're outside the diff>

## Poem        ← only if --poem
> <four-line rabbit-style verse about the PR>
```

Wrap the entire walkthrough body with HTML comment markers so re-runs can find-and-replace:

```
<!-- robot-review:start sha=<HEAD_SHA> -->
...content...
<!-- robot-review:end -->
```

### 7. Write inline findings

Each finding follows the CodeRabbit anatomy:

```
**🤖 RoBot review** — _⚠️ Critical (blocking)_

**<one-line subject>**

<one paragraph: WHY this matters>

```suggestion
<exact replacement for the lines this comment targets>
```

<!-- robot-review:inline -->
```

Substitutions per severity:
- critical → `_⚠️ Critical (blocking)_`
- major → `_🛠️ Major suggestion_`
- minor → `_🧹 Nitpick (non-blocking)_`
- question → `_❓ Question_`
- praise → `_✨ Praise_`

Only include the ` ```suggestion ` block when the fix is a concrete replacement for the targeted lines. If the fix needs broader context, put a ` ```diff ` block instead (illustrative only, not committable).

### 8. Validate before emitting

For each inline finding, verify:
1. The `path` exists in the PR's changed files.
2. The `line` is in the diff hunk (`RIGHT` side for added/context, `LEFT` for removed).
3. Multi-line: `start_line <= line`, both with `side` set.

Drop any finding that fails validation. Move it to the **Out of scope** section of the walkthrough instead.

### 9. Local report (default)

Write to `./.code-review/PR-<N>-<slug>.md`. Add `.code-review/` to `.gitignore` if absent (or `~/.gitignore_global` if the repo's `.gitignore` is locked).

Format: see `reference.md` § Local report.

### 10. Post to GitHub (only when --post or --post-only)

Build `/tmp/robot-review-<N>.json`:

```json
{
  "commit_id": "<PR_HEAD_SHA>",
  "event": "COMMENT",
  "body": "<walkthrough markdown>",
  "comments": [
    { "path": "...", "line": 42, "side": "RIGHT", "body": "..." },
    { "path": "...", "start_line": 60, "start_side": "RIGHT", "line": 64, "side": "RIGHT", "body": "..." }
  ]
}
```

`event` selection:
- Has critical → `REQUEST_CHANGES`
- `--profile strict` AND has major → `REQUEST_CHANGES`
- `--profile chill` AND no critical → `APPROVE`
- Otherwise → `COMMENT`

Post atomically:

```bash
gh api repos/<OWNER>/<REPO>/pulls/<N>/reviews \
  --method POST \
  --input /tmp/robot-review-<N>.json
```

If the POST returns 422, the most likely cause is a stale `commit_id` or a `line` not in the diff. Re-fetch `headRefOid`, re-validate lines, retry **once**, then surface the error to the user with the offending finding.

### 11. Confirm to user

Print:
- Path to local report (if written).
- GH URL of the posted review (if posted).
- Counts by severity.
- The verdict event (`COMMENT` / `REQUEST_CHANGES` / `APPROVE`).

## Idempotency on re-runs

When `--post` is run a second time on the same PR:
1. Delete the previous RoBot walkthrough comment if found (search PR comments for `<!-- robot-review:start`).
2. Dismiss the previous RoBot review (`gh api .../reviews/<id>/dismissals`).
3. Post the new one.

This keeps the PR clean across re-runs without manual cleanup.

## Anti-patterns to avoid

Full list in `reference.md`. Five worst:

1. **Hallucinated line numbers.** Always validate `path:line` against the parsed diff before emitting.
2. **Restating the diff.** The walkthrough captures INTENT, not "this PR changes X files".
3. **Nit-flood drowning real issues.** Cap nits at 5; suppress entirely without `--assertive`.
4. **Sycophantic praise.** Max 1 praise per review, and only when it's a genuine improvement worth naming.
5. **Style nits a linter catches.** Out of scope. Don't.
