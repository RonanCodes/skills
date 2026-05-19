---
name: gh-ship
description: Ship a feature branch through GitHub — open PR, watch PR checks, confirm merge, then monitor main-branch CI and verify auto-deploy. Use when a feature is ready to go from branch to production via GitHub. Sibling to /ro:cf-ship (that one runs the local pre-flight; this one drives the GitHub side).
category: development
argument-hint: [--title "<title>"] [--base main] [--squash|--merge|--rebase] [--no-merge]
allowed-tools: Bash(git *) Bash(gh *) Bash(curl *) Read
---

# GH Ship

Drive a feature from branch to production through GitHub. The PR gets opened, CI gets watched, merge gets confirmed, post-merge pipeline gets watched, and auto-deploy gets verified. If there's no auto-deploy wired up, offer to set it up.

## Usage

```
/ro:gh-ship                                 # open PR from current branch, full flow
/ro:gh-ship --title "✨ feat: add search"   # explicit title, skip the derive-from-commits step
/ro:gh-ship --base release/1.2              # base branch other than main
/ro:gh-ship --squash                        # squash-merge (default)
/ro:gh-ship --merge                         # merge commit
/ro:gh-ship --rebase                        # rebase-merge
/ro:gh-ship --no-merge                      # open + watch PR, stop before asking to merge
```

## Process

### 1. Sanity checks

- Current branch is NOT `main` / `master` / the base branch — fail fast with "checkout a feature branch first"
- Working tree is clean (`git status --porcelain` empty) — if not, bail and tell the user to commit first (do NOT auto-stash)
- Branch is pushed to origin (`git rev-parse @{u}` succeeds) — if not, `git push -u origin <branch>`
- `gh auth status` is logged in

### 2. Derive PR title + body

Unless `--title` given, derive from commits on this branch:

```bash
git log --format="%s" "${BASE}..HEAD"
```

- One commit → use its subject as the PR title verbatim
- Multiple commits → derive a single title from the dominant emoji+type (✨ feat / 🐛 fix / etc.), keep it under 70 chars; list all commit subjects in the body
- Always add a short **Summary** (3 bullets max) and **Test plan** (checklist) to the body

Use the repo's existing PR template if `.github/pull_request_template.md` exists.

### 3. Open the PR

```bash
gh pr create --base "$BASE" --head "$BRANCH" \
  --title "$TITLE" --body "$BODY"
```

Capture the PR number for the rest of the flow.

### 4. Watch PR checks

**First, check the per-repo CI config.** Some repos run with `wait_for_remote: false` in `.ronan-skills.json` (e.g., when GitHub Actions is billing-blocked or when the team has decided local pre-push validation is sufficient). If so, skip this step entirely and jump to step 5.

```bash
if [ -f .ronan-skills.json ]; then
  wait_for_remote=$(jq -r '.ci.wait_for_remote // true' .ronan-skills.json)
  if [ "$wait_for_remote" = "false" ]; then
    echo "skip: .ronan-skills.json has ci.wait_for_remote=false — trusting local pre-push quality"
    # Continue to step 5 (or step 6 if auto_merge_on_local_pass=true)
  fi
fi
```

If `wait_for_remote` is true (or the config file is missing), kick off a Monitor watching the PR's check run:

```bash
until s=$(gh run list --branch "$BRANCH" --limit 1 --json status,conclusion \
  -q '.[0] | "\(.status) \(.conclusion)"'); [[ "$s" == completed* ]]; do
  echo "pr-ci: $s"
  sleep 20
done
echo "pr-ci: $s"
```

Report status updates as they change (in_progress → completed).

On completion:

- **pass** — proceed to step 5
- **failure** — fetch the failing logs (`gh run view <id> --log-failed | tail -50`), show the user the first clear error, stop. Offer to fix.

If the PR has required status checks and they haven't all reported yet, wait for them too — `gh pr checks <num>` is the source of truth (not just workflow runs).

### 5. Ask to merge (unless `--no-merge`)

**Check `.ronan-skills.json` `ci.auto_merge_on_local_pass` first.** When true (and the local pre-push hook already validated format + lint + typecheck + test + build), skip the AskUserQuestion and proceed straight to step 6:

```bash
auto_merge=$(jq -r '.ci.auto_merge_on_local_pass // false' .ronan-skills.json 2>/dev/null || echo false)
if [ "$auto_merge" = "true" ]; then
  echo "auto-merge: .ronan-skills.json has ci.auto_merge_on_local_pass=true — merging without prompt"
  # Skip the question, go to step 6.
fi
```

Otherwise, via `AskUserQuestion`:

> PR #N passed checks. Merge to `$BASE` now? (Options: squash / merge / rebase / not yet)

Default option matches the `--squash|--merge|--rebase` flag (squash if none given). On "not yet", print the PR URL and exit cleanly.

### 6. Merge

Read merge_method from `.ronan-skills.json` (defaults to `squash`) and use `--admin` to bypass branch protection when remote CI hasn't reported (because we're trusting local pre-push):

```bash
merge_method=$(jq -r '.ci.merge_method // "squash"' .ronan-skills.json 2>/dev/null || echo squash)
admin_flag=""
if [ "$(jq -r '.ci.wait_for_remote // true' .ronan-skills.json 2>/dev/null)" = "false" ]; then
  admin_flag="--admin"   # bypass "checks required" branch protection
fi
gh pr merge "$NUM" --"$merge_method" --delete-branch $admin_flag
```

If `gh pr merge` fails with "Not possible to fast-forward" after the merge itself succeeded, that's gh trying to update local main — fix with `git fetch origin && git reset --hard origin/main` (safe here because local main hasn't diverged intentionally).

Verify via `gh pr view <num> --json state` → expect `MERGED`.

### 7. Watch post-merge pipeline

Immediately start monitoring CI on the base branch:

```bash
until s=$(gh run list --branch "$BASE" --limit 1 --json status,conclusion \
  -q '.[0] | "\(.status) \(.conclusion)"'); [[ "$s" == completed* ]]; do
  echo "deploy: $s"
  sleep 25
done
echo "deploy: $s"
```

Report status updates. Don't just watch the workflow as a whole — if the workflow has a `deploy` job specifically, name it in the report ("deploy: in_progress", "deploy: skipped", "deploy: failure", "deploy: success").

### 8. Verify auto-deploy

Three possible outcomes after the base-branch workflow finishes:

#### a) Workflow ran a deploy job → success

Report the deployed URL if derivable (from the workflow log, or from the `wrangler.jsonc` / `fly.toml` / `vercel.json`). Done.

#### b) Workflow ran a deploy job → failure

Fetch the logs, surface the specific error. Common failures:

| Symptom | Cause | Fix |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` empty | Secret not in `production` environment (if workflow uses `environment: production`) | Set via `gh secret set ... --env production` |
| `gh secret set` returns 401 | Current `gh` token lacks the right scope | `gh auth refresh -h github.com -s admin:repo_hook` (or set secrets manually) |
| `Not possible to fast-forward` (post-merge) | Local main diverged from origin | `git fetch && git reset --hard origin/<base>` |
| Migration `wrangler d1 ... --remote` fails | `CLOUDFLARE_ACCOUNT_ID` missing | Same as above |

Offer to fix. Don't silently retry.

#### c) Workflow has NO deploy job (or the job was skipped with no conditions matching)

Detect by checking `.github/workflows/*.yml` for any job with `wrangler deploy`, `fly deploy`, `vercel deploy`, etc. If none, tell the user:

> Merged to `$BASE`, but I don't see any auto-deploy wired up in `.github/workflows/`.
>
> Would you like me to add a push-to-`$BASE` deploy job? I'd need to know the deploy target (Cloudflare Workers / Fly / Vercel / other).

If they say yes, delegate to the appropriate scaffold step:

- **Cloudflare Workers** — add a `deploy` job that does `pnpm wrangler deploy`, gated on the existing `test` job, under `environment: production`, reading `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` from env secrets. Template below.
- **Fly** — `flyctl deploy --remote-only` with `FLY_API_TOKEN`
- **Vercel** — `vercel deploy --prod` with `VERCEL_TOKEN` (though `/ro:cf-ship` would already have migrated away from this)
- **Other** — ask what tool and help write the job

### 9. Report

Summarise:

- PR number + URL
- Merge commit SHA on base
- Deploy status + deployed URL (if any)
- Any follow-ups (secrets to set, next manual step)

## Auto-deploy job template (Cloudflare Workers)

Drop this into `.github/workflows/ci.yml` after the existing `test` job:

```yaml
deploy:
  name: Deploy to Cloudflare Workers
  needs: test
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  runs-on: ubuntu-latest
  environment: production
  concurrency:
    group: deploy-production
    cancel-in-progress: false
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      with: { version: 9 }
    - uses: actions/setup-node@v4
      with: { node-version: 22, cache: pnpm }
    - run: pnpm install --frozen-lockfile
    - run: pnpm build
    - name: Apply D1 migrations
      run: pnpm wrangler d1 migrations apply <db-name> --remote
      env:
        CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
    - name: Deploy worker
      run: pnpm wrangler deploy
      env:
        CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
        CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

Then set secrets on the `production` environment (not repo-level, so non-main branches can't read them):

```bash
set -a && source "$(ro context env)" && set +a
unset GITHUB_TOKEN GH_TOKEN   # see gotcha below
REPO=<owner>/<repo>

gh secret set CLOUDFLARE_API_TOKEN --env production --repo $REPO --body "$CLOUDFLARE_API_TOKEN"
gh secret set CLOUDFLARE_ACCOUNT_ID --env production --repo $REPO --body "$CLOUDFLARE_ACCOUNT_ID"
```

### `HTTP 401: Bad credentials` on `gh secret set`

Two causes, in this order of likelihood:

1. **`GITHUB_TOKEN` from `~/.claude/.env` is shadowing the gh keychain.** Sourcing `~/.claude/.env` to pull `CLOUDFLARE_API_TOKEN` also loads `GITHUB_TOKEN`, and gh prefers env-var auth over the keychain. If that env token has narrower scopes, you get `HTTP 401: Bad credentials` on the public-key fetch — even though `gh api` on the same endpoint works. Fix: `unset GITHUB_TOKEN GH_TOKEN` right after sourcing, before any gh call.
2. **Actual scope gap.** Classic PAT is missing what's needed for env secrets. Fix: `gh auth refresh -h github.com -s admin:repo_hook`.

Always pass `--repo <owner>/<name>` explicitly when calling from a subshell or a directory where the remote isn't obvious — gh's repo auto-detection is flaky.

## Safety

- Do NOT auto-merge without explicit user confirmation (even when CI passes) — the "ask to merge" step is non-skippable
- Do NOT force-push to the PR branch during the flow
- Do NOT delete the feature branch until merge completes successfully (gh does this with `--delete-branch` after merge)
- If post-merge CI fails, do NOT auto-revert — surface the error, let the user decide
- Never print secret values; refer to them by name only

## See also

- `/ro:cf-ship` — local pre-flight deploy gate (lint/test/build/migrations/smoke) — run before opening the PR
- `/ro:commit` — emoji conventional commit format (used for commits before shipping)
- `/ro:cloudflare-dns` — if the deploy job succeeds but you also need to point a custom domain
- `/ro:git-guardrails` — destructive-command hook that complements this skill's safety rules
