---
name: migrate-to-astro
description: Migrate an existing static-leaning web app (Vercel-hosted Astro, VPS-hosted Astro, Next.js marketing site, plain HTML site, etc.) to Astro 5 on Cloudflare Workers + Sentry EU + PostHog EU. Walks the cutover sequence in the order that actually works (not the order the docs suggest), with explicit checks for every one of the twelve gotchas captured in the LLM wiki research vault. Sister skill to /ro:migrate-to-tanstack — for sites that don't need a real server runtime, just edge-cached HTML + a thin Worker for /api/* and runtime config injection. Use when user wants to migrate, port, move, rewrite, or convert an Astro site to Cloudflare Workers — from Vercel, Hetzner/DigitalOcean VPS, Pages, Render, etc.
category: project-setup
argument-hint: [--strategy branch|fresh] [--keep-data] [--no-i18n]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(curl *) Bash(jq *) Bash(grep *) Bash(find *) Bash(awk *) Bash(sed *) Read Write Edit Glob Grep
---

# Migrate To Astro

Move an existing site (Astro on Vercel/VPS, plain Next.js marketing, hand-rolled HTML) onto the canonical Astro 5 + Cloudflare Workers stack. Defers everything that's the same as a fresh scaffold to `/ro:new-astro-app`; this skill's value is the **cutover sequence** for an already-live domain.

The full backstory and per-gotcha rationale lives in `[[astro-cf-workers-migration-gotchas]]` (LLM wiki research vault, 2026-05-04). That doc is this skill's spec — every numbered step below references the gotcha number. **Read it first if you've never run this skill.**

## Usage

```
/ro:migrate-to-astro                          # interactive, picks up the cwd as the source
/ro:migrate-to-astro --strategy fresh         # start a new repo, port content over
/ro:migrate-to-astro --strategy branch        # in-place on a feature branch (default)
```

## Process

### 0. Source existing credentials and pick the right CF context

Before anything else, make sure ro is resolving the right context for this repo. Three options, cleanest first:

```bash
# Option A — drop a .ro-context file at the repo root (committed, auto-resolves
# for everyone who clones it; preferred for any repo with a stable owner/account)
echo simplicity > .ro-context

# Option B — already declared via a cwd-glob rule in ~/.claude/contexts.json
#   (e.g. `~/Github-Simplicity/**` → `simplicity`)
ro context where   # confirm the rule is hitting

# Option C — manual session override, useful for one-off ports outside any rule
ro context use <client-name>
```

Then load the env:

```bash
set -a; source "$(ro context env)"; set +a
```

If the source domain is in a different CF account than the one currently active, the deploy will fail with cryptic auth errors and the cutover will partially break. Always verify:

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?name=<host>" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[] | {id, account_id, account_name}'
```

The `account_id` returned must match `$CLOUDFLARE_ACCOUNT_ID`. If not, switch context.

### 1. Audit (never skip)

What's there now? Run in the source repo:

```bash
# What's the current adapter?
grep -E "@astrojs/(vercel|netlify|cloudflare|node)" package.json
# What output mode?
grep -E "output:\s*['\"](static|server|hybrid)" astro.config.*
# Any old observability we're replacing?
grep -rn "umami\|glitchtip\|sentry\|posthog" src/ | head
# What's the deploy mechanism?
ls .github/workflows/  vercel.json  netlify.toml  Dockerfile  2>/dev/null
```

Capture the output — the user needs to know which migrations they're signing up for.

### 2. Apply the canonical scaffold (delegate to /ro:new-astro-app patterns)

Run the same edits `/ro:new-astro-app` would on a fresh project, but in-place:

- Swap adapter to `@astrojs/cloudflare`, `output: 'server'`, `imageService: 'compile'` — gotcha #3
- Add the postbuild step writing `dist/.assetsignore` — gotcha #4
- `pnpm add sharp` — gotcha #12
- Add `wrangler.jsonc` (with `routes: [{ custom_domain: true }]` blocks for the live host)
- Mirror the i18n key references but keep the project's existing translations
- Add prettier/eslint/vitest/playwright configs from the canonical set — gotchas #9, #10
- Bulk-add `export const prerender = true;` to every page under `src/pages/` except `api/` — gotcha #11

### 3. Replace observability (always)

If the source has Umami / GlitchTip / Plausible / native Vercel analytics, rip out and replace with the runtime-injected Sentry + PostHog setup:

- Delete the old script tags from `Layout.astro`
- Add the canonical `src/lib/{sentry,posthog,runtime-config}.ts` + `src/pages/api/config.ts`
- Update `src/env.d.ts` with the `CloudflareEnv` types
- Wire **footer-attached Sentry feedback button** (gotcha-adjacent: this is the Ronan default, not just a migration step). See `/ro:sentry` "Footer-attached feedback button" section.

If retaining historical analytics data is a concern, leave the source's Umami running on a `analytics.<host>` subdomain for ~30 days while PostHog ingestion stabilises, then export Umami CSV before tearing down.

### 4. Replace stale framework references

If migrating from Vercel:

- Delete `vercel.json`, `.github/workflows/preview.yml`, any `_middleware.ts` Vercel-edge code
- Replace `context.locals.vercel?.edge?.geo?.country` with `request.headers.get("CF-IPCountry")` — gotcha #8
- Drop `@astrojs/vercel`, `@vercel/analytics`, `@vercel/speed-insights` from `package.json`
- `src/env.d.ts`: drop `EdgeLocals` import; declare `CloudflareEnv` instead

If migrating from a VPS-hosted Astro: usually less to delete — the source repo has just `astro` + a deploy script. Drop the Dockerfile, the deploy script, and any health-check endpoints that won't make sense at the edge.

### 5. Fix every pre-existing typecheck error (always)

The pre-Astro-5 codebase likely has `import { type ImageMetadata } from "astro:assets"` in multiple files (gotcha #2). Rewrite globally:

```bash
grep -rl 'import.*type ImageMetadata.*from "astro:assets"' src/ \
  | xargs sed -i '' -E 's|import \{ ?Image, type ImageMetadata ?\} from "astro:assets";|import { Image } from "astro:assets";\nimport type { ImageMetadata } from "astro";|'
```

Also: `<!-- HTML comments -->` inside JSX expressions (`{condition ? (...)`, `.map(() => (...))`) cause prettier-plugin-astro and eslint-plugin-astro to choke (gotcha #1). Strip them or convert to `{/* ... */}`. Bulk-strip:

```bash
sed -i '' -E '/^[[:space:]]*\{\/\*.*\*\/\}[[:space:]]*$/d' <files>
```

Run `pnpm exec astro check` until it returns 0 errors. Don't skip this — `pnpm quality-checks:ci` calls it.

### 6. Set up CI + GH secrets (always, unless `--skip-ci`)

Mirror `/ro:new-astro-app`'s step 8: `.github/workflows/ci.yml` with three jobs (quality, e2e, deploy).

Provision the `Production` environment + 5 repo secrets:

```bash
gh api -X PUT repos/$OWNER/$REPO/environments/Production
for secret in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID SENTRY_AUTH_TOKEN SENTRY_DSN POSTHOG_PROJECT_KEY; do
  printf '%s' "${!secret}" | gh secret set "$secret" --env Production -R "$OWNER/$REPO"
done
```

Use the `sntrys_` org auth token for `SENTRY_AUTH_TOKEN` in CI (org-scoped, source-map upload), not the `sntryu_` user token.

### 7. The cutover (`--strategy branch`, default)

This is the only part of the skill that's destructive. **Triple-check everything is committed before this step.**

7a. **Verify the target token can do everything it needs.** Run all four probe calls — fail fast if any return `code: 10000`:

```bash
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=<host>" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result[0].id')

# Workers Scripts:Edit
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.success'

# Workers Domains (custom domain attach)
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/domains?zone_id=$ZONE_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.success'

# Zone:Read
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.success'
```

If `Worker Routes:Edit` is missing, that's fine — gotcha #5 has a workaround (skip routes in wrangler.jsonc the first time, attach domains by hand, add routes back).

7b. **Upload the Worker WITHOUT routes.** Temporarily remove the `routes` block from `wrangler.jsonc` (or `--no-routes`), set `workers_dev: true`, deploy:

```bash
pnpm exec wrangler deploy
# expect: "Uploaded <name>" + "register a workers.dev subdomain" prompt or success
```

The Worker now exists at `<name>.<subdomain>.workers.dev` (or just exists on the account). Test it directly via that URL before touching DNS.

7c. **Cutover — delete VPS DNS records, attach custom domains.** Need a token with `Zone DNS:Edit` (the `CLOUDFLARE_API_TOKEN_DNS_ONLY` token in the simplicity context worked):

```bash
# 1. List the live A/CNAME records
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=<host>" \
  -H "Authorization: Bearer $DNS_TOKEN" | jq '.result[] | {id, content}'

# 2. DELETE each one (gotcha #6 — override_existing_dns_record does NOT work, must delete manually)
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/<record_id>" \
  -H "Authorization: Bearer $DNS_TOKEN" | jq '.success'

# 3. Attach Workers custom domains for apex + www
for host in "<host>" "www.<host>"; do
  curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/domains" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
    -d "{\"environment\":\"production\",\"hostname\":\"$host\",\"service\":\"<worker-name>\",\"zone_id\":\"$ZONE_ID\"}" \
    | jq '{success, errors, hostname: .result.hostname, cert_status: .result.cert_status}'
done
```

The instant step 2 completes, the live site stops resolving from the VPS. Provisioning of the new TLS cert + DNS records on the CF side is usually <60s. Have the rollback script ready (re-create the deleted A records pointing to the original IP) just in case.

7d. **Add `routes` back to wrangler.jsonc** (gotcha #7) and redeploy with full vars:

```bash
pnpm exec wrangler deploy \
  --var SENTRY_DSN:"$SENTRY_DSN" \
  --var POSTHOG_PROJECT_KEY:"$POSTHOG_PROJECT_KEY" \
  --var POSTHOG_INGEST_HOST:"$POSTHOG_INGEST_HOST"
```

Now wrangler's deploy guard is satisfied (routes block exists, custom domains pre-bound), and every CI deploy is a pure code refresh.

### 8. Post-deploy verification (always, never skip)

```bash
# Live site headers — confirm CF (server: cloudflare in headers)
curl -sI "https://<host>/"

# Runtime config — DSN and phc_ should be present
curl -s "https://<host>/api/config" | jq '.'

# No /_image refs in homepage HTML (gotcha #3 + gotcha #11 verification)
curl -s "https://<host>/" | grep -ic "_image\?" || echo OK

# Logo loads from compiled WebP path
curl -s "https://<host>/" | grep -oE "/_astro/[^\"]+\.webp" | head -3

# Sentry initialised — open in browser, look for `[sentry] initialised` in console
```

If any of these fail, **don't roll forward** — debug. CF cache may serve the old VPS HTML for ~5 min on the same edge; if you need to bust faster, hit the cache-purge endpoint (needs `Zone:Cache Purge:Purge` scope on the token).

### 9. Decommission old infra (always, after live)

```bash
# Stop the old VPS (or unbind the domain at Vercel/Netlify/Pages)
# Remove the analytics subdomain tunnel (if Umami was self-hosted via CF Tunnel)
# Delete any CF Pages project that previously served this domain

# DON'T delete the source git tag yet — keep `pre-cloudflare-migration` as a rollback point
```

### 10. Final commit + PR

`/ro:commit` then `/ro:gh-ship` to open the migration PR. The commit/PR body should reference `[[astro-cf-workers-migration-gotchas]]` so future readers can trace decisions.

## Order-of-operations cheat sheet

```
0. context → 1. audit → 2. scaffold → 3. observability → 4. framework cleanup
→ 5. fix typecheck → 6. CI + secrets → 7a. probe token → 7b. upload Worker
→ 7c. CUTOVER (delete A, attach domain) → 7d. routes back + redeploy
→ 8. verify → 9. decommission → 10. commit
```

## Safety

- Tag the source state before any edits: `git tag pre-cloudflare-migration`
- Keep the original VPS / Vercel project up for 7 days post-cutover before tearing down (rollback path)
- DO NOT run step 7c without the rollback script (delete-record IDs + restore commands) prepped in a separate terminal

## Anti-patterns it guards against

Same list as `/ro:new-astro-app`, plus the migration-specific ones:

- ❌ Trusting the `override_existing_dns_record` flag (gotcha #6 — the flag is documented but doesn't work; manually delete records first)
- ❌ Running `wrangler deploy` with the `routes` block on first cutover before domains are attached (causes the 10000 auth error from gotcha #5)
- ❌ Skipping the `pnpm exec astro check` cleanup pass (gotchas #1 + #2 will surface as eslint/format failures in CI later, harder to diagnose)
- ❌ Removing the source repo's PostHog/Umami before the new project's events are confirmed flowing

## See also

- `[[astro-cf-workers-migration-gotchas]]` — the spec this skill implements
- `/ro:new-astro-app` — when you're starting fresh, no existing DNS to displace
- `/ro:cf-ship` — the deploy step (this skill calls it via `pnpm run deploy`)
- `/ro:cloudflare-dns` — for any extra subdomains beyond apex + www
- `/ro:sentry` — the "Footer-attached feedback button" section is the Ronan default for the `<button id="sentry-feedback-trigger">` placement
- `/ro:posthog` — for the project create + `phc_` provisioning
- `/ro:migrate-to-tanstack` — sister skill for sites that need a server runtime, not just edge HTML
