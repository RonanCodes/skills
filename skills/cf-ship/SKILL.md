---
name: cf-ship
description: Ship a TanStack Start / Cloudflare Workers app with pre-flight checks (typecheck + lint + test + D1 migrations + build + deploy). Use when user wants to deploy, ship, release, push, or go live with a Cloudflare Workers app. Handles secrets, D1 migrations, and a post-deploy smoke check.
category: deployment
argument-hint: [--skip-tests] [--skip-migrations] [--env <name>]
allowed-tools: Bash(pnpm *) Bash(wrangler *) Bash(curl *) Bash(git *) Read Edit
---

# CF Ship

Deploy a Cloudflare Workers app (TanStack Start on Path C) with a pre-flight gate. Prevents shipping broken code.

## Usage

```
/ro:cf-ship                       # full pipeline
/ro:cf-ship --skip-tests          # skip pnpm test (hotfix mode)
/ro:cf-ship --skip-migrations     # skip D1 migrations (schema unchanged)
/ro:cf-ship --env staging         # deploy to a non-default wrangler env
```

## Prerequisites

- `wrangler` authed. Three options in priority order:
  1. **`~/.claude/.env`** has `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` from `/ro:cloudflare-setup` (the default for this user). Source pattern:
     ```bash
     set -a && source "$(ro context env)" && set +a
     unset GH_TOKEN GITHUB_TOKEN   # ~/.claude/.env shadows gh CLI keychain — must unset before any gh call
     ```
     Always grep this file BEFORE asking the user to paste a token or run `wrangler login` — for already-onboarded providers, the value is there.
  2. `wrangler login` (browser OAuth) — fine for one-off interactive runs
  3. `${CLAUDE_PLUGIN_DATA}/.env` (legacy, prefer `~/.claude/.env`)
- `wrangler.toml` in repo root with a valid `main` or TanStack Start preset configured
- Clean or near-clean git tree (skill warns on uncommitted changes)

## Process

### 1. Sanity check

Run in parallel:

```bash
git status --short
wrangler whoami
git rev-parse HEAD
```

If uncommitted changes exist, warn the user — offer to proceed anyway or abort. Print the current commit SHA and branch so there's a paper trail of what's shipping.

### 2. Pre-flight gates

Run in this order. **Stop on first failure** — do not try to "fix forward" without asking.

```bash
pnpm typecheck          # tsc --noEmit, strict mode
pnpm lint               # eslint .
pnpm format:check       # prettier --check .
pnpm test               # vitest run (skip if --skip-tests)
```

If any fails, surface the output and stop. Suggest `/ro:commit` after the fix.

### 3. D1 migrations

Unless `--skip-migrations`:

```bash
pnpm drizzle-kit generate                              # generate any pending migrations
wrangler d1 migrations list <db-name> --remote          # show what's pending remotely
```

Read the db name from `wrangler.toml` (`[[d1_databases]] database_name`). Show the user the list. If migrations are pending, confirm before applying:

```bash
wrangler d1 migrations apply <db-name> --remote
```

Apply local too (keeps dev DB matching):
```bash
wrangler d1 migrations apply <db-name> --local
```

### 4. Secrets check

List current secrets and compare against `.dev.vars`:

```bash
wrangler secret list
grep -E '^[A-Z_]+=' .dev.vars 2>/dev/null | cut -d= -f1
```

If `.dev.vars` has a key that's NOT in `wrangler secret list`, warn the user and offer to push it:

```bash
wrangler secret put KEY_NAME        # prompts for value
```

Never auto-push secrets without confirmation.

### 5. Build + deploy

```bash
pnpm build
wrangler deploy                     # add --env <name> if --env passed
```

Capture the deployed URL from wrangler's output (`https://<worker>.<account>.workers.dev` or custom domain).

### 6. Smoke check

```bash
curl -sfI <deployed-url> | head -1        # expect HTTP/2 200 or 301
```

If it returns non-2xx/3xx, surface it immediately. Offer to tail logs:

```bash
wrangler tail
```

### 7. Tag + report

Offer to tag the release (optional):

```bash
git tag -a "deploy-$(date +%Y%m%d-%H%M%S)" -m "🚀 deploy: $(git log -1 --pretty=%s)"
```

Report to user: commit SHA, deployed URL, migrations applied, secrets status, smoke-check result.

## Failure modes

- **`typecheck` fails** — stop. Fix types, commit via `/ro:commit`, re-run `/ro:cf-ship`.
- **`test` fails** — stop. Don't use `--skip-tests` as a habit; treat red tests as the signal they are.
- **Migration apply errors** — common cause: migration was generated against a stale schema. Re-run `drizzle-kit generate` with a clean working DB first.
- **`wrangler deploy` fails on `compatibility_date`** — bump to today's date in `wrangler.toml`.
- **Smoke check 500** — `wrangler tail` immediately; usually a missing secret or bad D1 binding.

## Safety

- Never `--skip-tests` + `--skip-migrations` together without explicit user confirmation
- Never deploy to prod (`--env production`) without showing current vs new commit first
- `wrangler delete` / `wrangler d1 delete` are NOT part of this skill — refuse if asked

## See also

- `/ro:commit` — emoji commits (use before shipping)
- `/ro:new-tanstack-app` — scaffold that this skill ships
- `/ro:cloudflare-dns` — add a custom domain after first deploy
