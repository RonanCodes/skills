---
name: new-astro-app
description: Orchestrate scaffolding a new Astro app on the canonical stack (Astro 5 + `output: 'server'` on @astrojs/cloudflare + Sentry EU + PostHog EU + pnpm). For marketing/landing/portfolio sites where most pages are static and only a thin runtime exists for /api routes. Sister skill to /ro:new-tanstack-app — Astro path of the stack-decision-map's "App shape → Marketing site / static-leaning" leaf. Dispatches to /ro:sentry, /ro:posthog, /ro:cloudflare-dns, /ro:cf-ship like its TanStack twin. Use when user wants to start, create, scaffold, bootstrap, or kick off a new Astro project / marketing site / landing page / blog.
category: project-setup
argument-hint: <app-name> [--posthog] [--sentry] [--uptime] [--domain <host>] [--no-i18n] [--skip-deploy] [--skip-ci] [--interactive]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(corepack *) Bash(mkdir *) Bash(cp *) Bash(jq *) Read Write Edit
---

# New Astro App (orchestrator)

Scaffolds a new Astro 5 site on Cloudflare Workers using the same stack as the sister `/ro:new-tanstack-app`. Output mode `'server'` with prerender-by-default for marketing pages, observability via Sentry + PostHog (EU region for both), pnpm-pinned, GitHub Actions deploy on merge to `main`.

## Usage

```
/ro:new-astro-app my-site --posthog --sentry --domain my-site.com
/ro:new-astro-app my-site --interactive
/ro:new-astro-app my-site --no-i18n --skip-deploy
```

Sub-flags map to the same dispatched sub-skills as the TanStack orchestrator. See `/ro:new-tanstack-app` for `--posthog`, `--sentry`, `--uptime`, `--domain` semantics — they're identical here, just running against an Astro project tree.

## What it actually does

- Scaffolds a fresh Astro 5 project with TypeScript strict
- Wires `@astrojs/cloudflare` adapter with `output: 'server'`, `imageService: 'compile'`, `platformProxy: { enabled: true }`
- Adds the Sentry vite-plugin for source-map upload + the runtime-config endpoint (`/api/config`) so DSN + PostHog `phc_` aren't baked into the bundle
- Optional i18n routing scaffold (en + nl by default; pass `--no-i18n` to skip)
- pnpm + `packageManager` field pin, `pnpm.onlyBuiltDependencies` allowlist for `@sentry/cli`, `esbuild`, `sharp`, `workerd`
- ESLint flat config + Prettier with `prettier-plugin-astro` + Vitest + Playwright + the smoke e2e tests
- Bakes in every fix from `[[astro-cf-workers-migration-gotchas]]` from day one
- GitHub Actions: quality (format/lint/typecheck/build/test) + e2e + deploy on `main`
- Deploys via `/ro:cf-ship` and binds the custom domain via `/ro:cloudflare-dns`

## Prerequisites

- Node ≥22, pnpm ≥10
- `~/.claude/.env` (or active context via `ro context use <name>`) populated with `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`. If unset, run `/ro:cloudflare-setup` first.
- For `--sentry`: `SENTRY_AUTH_TOKEN`, `SENTRY_ORG` (use `sntrys_` org-scoped token in CI; `sntryu_` user token for project create)
- For `--posthog`: `POSTHOG_PERSONAL_API_KEY` (`phx_` admin), region host

## Interactive mode (`--interactive`)

Same flow as `/ro:new-tanstack-app --interactive`: walk through the project's open questions one by one with `AskUserQuestion`. Astro-specific decisions:

- **i18n?** Most marketing/landing-page sites need only one language; default off. Enable for `nl`, `de`, etc. when the audience demands it.
- **CMS?** `src/content/` (the built-in collections — recommended for blogs / case studies) vs no content layer (pages-only).
- **Sentry feedback widget placement** — always footer-attached, never floating (see `/ro:sentry` "Footer-attached feedback button" section). This is a hard default; don't ask.

## Process

### 1. Baseline scaffold (always)

```bash
pnpm create astro@latest <app-name> -- --template minimal --typescript strict --git --install
cd <app-name>
```

Pin pnpm:

```bash
corepack use pnpm@10.26.1
```

### 2. Wire Cloudflare adapter (always)

```bash
pnpm add @astrojs/cloudflare sharp posthog-js @sentry/browser
pnpm add -D @sentry/vite-plugin wrangler
```

Edit `astro.config.mjs`:

```js
import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";
import { sentryVitePlugin } from "@sentry/vite-plugin";
import { execSync } from "node:child_process";

const release = (() => {
  if (process.env.VITE_RELEASE) return process.env.VITE_RELEASE;
  try { return execSync("git rev-parse --short HEAD", { encoding: "utf8" }).trim(); }
  catch { return "dev"; }
})();

const sentryAuthToken = process.env.SENTRY_AUTH_TOKEN;
const sentryPlugin = sentryAuthToken ? sentryVitePlugin({ /* ... see /ro:sentry */ }) : null;

export default defineConfig({
  output: "server",
  adapter: cloudflare({
    imageService: "compile",          // gotcha #3 — don't use 'passthrough' with assets binding
    platformProxy: { enabled: true },
  }),
  vite: {
    define: { __APP_RELEASE__: JSON.stringify(release) },
    build: { sourcemap: true },
    plugins: [...(sentryPlugin ? [sentryPlugin] : [])],
  },
});
```

Add to `package.json`:

```jsonc
{
  "packageManager": "pnpm@10.26.1",
  "scripts": {
    "build": "astro build",
    "postbuild": "echo _worker.js > dist/.assetsignore",   // gotcha #4
    "deploy": "pnpm run build && wrangler deploy",
    // ... format / lint / typecheck / test / test:e2e / quality-checks:ci
  },
  "pnpm": {
    "onlyBuiltDependencies": ["@sentry/cli", "esbuild", "sharp", "workerd"]
  }
}
```

Create `wrangler.jsonc`:

```jsonc
{
  "name": "<app-name>",
  "compatibility_date": "<today>",
  "compatibility_flags": ["nodejs_compat"],
  "main": "./dist/_worker.js/index.js",
  "assets": { "directory": "./dist", "binding": "ASSETS" },
  "observability": { "enabled": true },
  "routes": [
    { "pattern": "<host>", "custom_domain": true },
    { "pattern": "www.<host>", "custom_domain": true }
  ],
  "vars": {
    "SENTRY_DSN": "",
    "POSTHOG_PROJECT_KEY": "",
    "POSTHOG_INGEST_HOST": "https://eu.i.posthog.com"
  }
}
```

### 3. Default-prerender every page (always)

Astro 5 with `output: 'server'` defaults to dynamic. Marketing sites should prerender by default; only `/api/*` runs at the edge:

```bash
find src/pages -name "*.astro" -not -path "*/api/*" \
  | while read f; do
      grep -q "export const prerender" "$f" && continue
      awk 'NR==1{print; print "export const prerender = true;"; next} 1' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
```

Run this **after** every new page is added too — bake it into the project's `pre-commit` hook or document it in CLAUDE.md.

### 4. Runtime config endpoint + observability libs (always when `--sentry` or `--posthog`)

Copy from the canonical reference (`ronanconnolly-dev`):

- `src/lib/runtime-config.ts` — fetches `/api/config`, memoised
- `src/lib/sentry.ts` — lazy init, EU region, replay + feedback (see `/ro:sentry` for the full file). **Footer-attached feedback button is the Ronan default — `autoInject: false` + `attachTo` wiring on every project.**
- `src/lib/posthog.ts` — lazy init, EU ingest, autocapture, session recording, test-user filter (uses `@<your-domain>` test emails so the project's "Internal & Test Accounts" filter excludes them with one rule)
- `src/pages/api/config.ts` — returns `SENTRY_DSN`, `POSTHOG_PROJECT_KEY`, `POSTHOG_INGEST_HOST` from `locals.runtime.env`, cached 5min

### 5. Tooling stack (always)

```bash
pnpm add -D \
  prettier prettier-plugin-astro \
  eslint @eslint/js typescript-eslint eslint-plugin-astro globals \
  @astrojs/check typescript \
  vitest jsdom @types/jsdom \
  @playwright/test
```

Configs (mirror the simplicity-labs-site reference repo verbatim — they bake in gotchas #1, #9, #10):

- `prettier.config.js` (with `prettier-plugin-astro`)
- `.prettierignore` (always include `.claude/`, `wiki/`, `CLAUDE.md`, `README.md`, `TASKS.md` — gotcha #9)
- `eslint.config.js` (flat config with `globals.browser` + `globals.node` — gotcha #10)
- `playwright.config.ts` (webServer: `pnpm exec astro dev --port 4321`)
- `vitest.config.ts` (jsdom env)
- `e2e/homepage.spec.ts` (smoke: every key route renders without console errors)

### 6. Sentry / PostHog provisioning (`--sentry` / `--posthog`)

Dispatch:

- `--sentry` → `/ro:sentry project create --name <app-name>` to mint the project + DSN, then write `SENTRY_DSN` into `~/.claude/.env`
- `--posthog` → `/ro:posthog project create --name "<App Name>"` for the `phc_`, write to env

For both, follow `/ro:sentry`'s guidance on **footer-attached feedback button** — autoInject:false + footer trigger. Every Ronan Astro app has the same UX.

### 7. UptimeRobot (`--uptime`, post-deploy)

`/ro:uptimerobot monitor create --url https://<host>/ --type http --interval 5` — same as TanStack flow.

### 8. CI workflow (always, unless `--skip-ci`)

Write `.github/workflows/ci.yml` with three jobs (mirror `simplicity-labs-site/.github/workflows/ci.yml`):

- `quality` (format + lint + typecheck + build + test)
- `e2e` (Playwright, depends on quality)
- `deploy` (depends on both, gated on `main` push, environment: `Production`)

Deploy job:

```yaml
- run: >
    pnpm exec wrangler deploy
    --var SENTRY_DSN:"$SENTRY_DSN"
    --var POSTHOG_PROJECT_KEY:"$POSTHOG_PROJECT_KEY"
    --var POSTHOG_INGEST_HOST:"$POSTHOG_INGEST_HOST"
```

Public-by-design keys ride in via `--var`, not `wrangler secret put`.

### 9. Domain + first deploy (`--domain <host>`, always unless `--skip-deploy`)

For a fresh project (no existing DNS displaces), the wrangler `routes: [{ custom_domain: true }]` block plus `/ro:cloudflare-dns` for any extra subdomains is enough. If the domain already has VPS-pointing records, dispatch to `/ro:migrate-to-astro` instead — the cutover sequence is different.

```bash
/ro:cf-ship                               # build + deploy
/ro:cloudflare-dns add www.<host> <ip>    # only if extra subdomains needed
```

### 10. Final commit — `/ro:commit`

Single commit with the standard emoji-conventional format.

## Output summary

After this skill runs the project should:

- Build clean: `pnpm quality-checks:ci` exits 0
- Deploy clean: `pnpm exec wrangler deploy` exits 0, hostname+www both bound
- Live: `/api/config` returns the DSN + phc_, no `/_image?...` URLs in HTML, no `/favicon.svg` 404s
- CI: green on first PR

## Anti-patterns it guards against

- ❌ `imageService: "passthrough"` (gotcha #3 — breaks `<Image>`)
- ❌ Forgetting `prerender = true` on marketing pages (gotcha #11)
- ❌ Auto-inject Sentry feedback widget (Ronan default — footer button only)
- ❌ Baking DSN/keys into the build (`PUBLIC_*` env vars) — use runtime-config
- ❌ Hardcoding `ronanconnolly.dev` / personal email in JSON-LD or footer copy
- ❌ Missing `dist/.assetsignore` postbuild step (gotcha #4)

## See also

- `[[astro-cf-workers-migration-gotchas]]` (LLM wiki research vault) — the twelve gotchas this skill bakes in
- `/ro:migrate-to-astro` — when there's an existing site to port
- `/ro:new-tanstack-app` — when the project actually needs a server runtime, not just a marketing surface
- `[[stack-decision-map]]` — when you're not sure which to pick
