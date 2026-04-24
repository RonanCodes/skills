---
name: testing-stack
description: Wire the canonical testing + API-docs stack into a TanStack Start + Cloudflare Workers app. Installs Vitest (unit + integration), Playwright (e2e + visual), Bruno (API collection with local/production/mock envs), Zod + @asteasolutions/zod-to-openapi (served at /api/openapi), Scalar docs UI (at /api/docs), and Prism mock server (FE-dev fallback on :4010). Use when user wants to add tests, API tests, API docs, OpenAPI, Swagger-style docs, a mock server, contract testing, or bruno to a TanStack Start app. Invoked automatically by /ro:new-tanstack-app.
category: testing
argument-hint: [install] [--no-bruno] [--no-mock] [--no-docs]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(pnpm dlx *) Bash(git *) Read Write Edit
---

# Testing Stack

Scaffold the six-layer testing and API-docs pattern documented in `connections-helper/docs/adr/0001-testing-and-docs-stack.md`.

## Usage

```
/ro:testing-stack install              # full stack
/ro:testing-stack install --no-bruno   # skip Bruno collection
/ro:testing-stack install --no-mock    # skip Prism mock server
/ro:testing-stack install --no-docs    # skip /api/openapi + /api/docs (keeps Vitest + Playwright + Bruno only)
```

Defaults install everything. Opt-outs are for unusual cases (e.g. the app is not an HTTP API).

## What you get

Six layers, one OpenAPI spec feeding all of them:

1. **Vitest unit** — `src/**/*.test.{ts,tsx}`
2. **Vitest integration** — `tests/integration/**/*.test.ts`, hits real upstreams
3. **Playwright e2e** — `e2e/**/*.spec.ts`, Chromium, webServer spins up dev
4. **Bruno API collection** — `/bruno/` with local/production/mock envs
5. **Zod + OpenAPI + Scalar** — spec at `/api/openapi`, docs at `/api/docs`
6. **Prism mock server** — FE-dev fallback on `:4010` via `pnpm mock`

All six run on every PR via GitHub Actions jobs that gate deploy.

## Prerequisites

- TanStack Start + Cloudflare Workers project already scaffolded (typical caller: `/ro:new-tanstack-app`)
- `pnpm` as package manager
- `package.json` with a `dev` script running on port 3000

## Process

### 1. Install dependencies

```bash
# Unit + e2e + harness
pnpm add -D vitest @testing-library/react @testing-library/jest-dom jsdom
pnpm add -D @playwright/test start-server-and-test
pnpm dlx playwright install

# Bruno (skip if --no-bruno)
pnpm add -D @usebruno/cli

# OpenAPI + docs + mock (skip if --no-docs)
pnpm add zod @asteasolutions/zod-to-openapi
pnpm add -D @stoplight/prism-cli tsx   # skip tsx + prism-cli if --no-mock
```

If `@stoplight/prism-cli` pulls a transitively vulnerable lodash, add a pnpm override to `package.json`:

```jsonc
"pnpm": {
  "overrides": {
    "lodash@<4.17.24": ">=4.17.24"
  }
}
```

### 2. Vitest configs

**`vitest.config.ts`** (unit):

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}', 'tests/unit/**/*.test.{ts,tsx}'],
    exclude: ['e2e/**', 'tests/integration/**', 'node_modules/**', 'dist/**'],
    passWithNoTests: true,
  },
})
```

**`vitest.integration.config.ts`** (integration, real upstreams):

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    environment: 'node',
    include: ['tests/integration/**/*.test.{ts,tsx}'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
    retry: 1,
  },
})
```

### 3. Playwright config

**`playwright.config.js`**:

```js
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  // Visual regression in its own workflow; opt in via PLAYWRIGHT_VISUAL=1.
  testIgnore:
    process.env.PLAYWRIGHT_VISUAL === '1' ? undefined : ['**/visual.spec.ts'],
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'on',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'pnpm dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
})
```

### 4. Zod schemas + OpenAPI spec (skip if `--no-docs`)

**`src/server/schemas.ts`** — define request/response schemas. Every schema gets a `description`. The 2–3 headline response schemas also get a realistic `example`:

```ts
import { z } from 'zod'
import { extendZodWithOpenApi } from '@asteasolutions/zod-to-openapi'
extendZodWithOpenApi(z)

export const ErrorResponse = z.object({ error: z.string() }).openapi('ErrorResponse', {
  description: 'Standard error envelope returned for 400, 404, and 429 responses.',
  example: { error: 'Invalid input' },
})

// ... more schemas, with .openapi(name, { description, example? }) on each
```

**`src/server/validate.ts`** — shared helper:

```ts
import type { ZodType } from 'zod'

export function jsonError(message: string, status = 400) {
  return Response.json({ error: message }, { status })
}

export function validate<T>(schema: ZodType<T>, input: unknown) {
  const parsed = schema.safeParse(input)
  if (parsed.success) return { ok: true as const, data: parsed.data }
  return { ok: false as const, response: jsonError(parsed.error.issues[0].message) }
}
```

**`src/server/openapi.ts`** — register paths, build document:

```ts
import { z } from 'zod'
import { OpenApiGeneratorV31, OpenAPIRegistry } from '@asteasolutions/zod-to-openapi'
import * as schemas from './schemas'

const registry = new OpenAPIRegistry()

// registry.registerPath({ method, path, tags, request, responses }) per route

export function buildOpenApiDocument(opts: { servers?: Array<{ url: string; description?: string }> } = {}) {
  return new OpenApiGeneratorV31(registry.definitions).generateDocument({
    openapi: '3.1.0',
    info: { title: 'My API', version: '0.1.0', description: 'Interactive docs at [/api/docs](/api/docs).' },
    servers: opts.servers ?? [{ url: 'https://example.com' }],
  })
}
```

### 5. `/api/openapi` and `/api/docs` routes (skip if `--no-docs`)

**`src/routes/api/openapi.ts`** — origin-aware server URL, per-origin memoisation:

```ts
import { createFileRoute } from '@tanstack/react-router'
import { buildOpenApiDocument } from '../../server/openapi'

const cache = new Map<string, unknown>()

export const Route = createFileRoute('/api/openapi')({
  server: {
    handlers: {
      GET: ({ request }) => {
        const origin = new URL(request.url).origin
        if (!cache.has(origin)) cache.set(origin, buildOpenApiDocument({ servers: [{ url: origin }] }))
        return Response.json(cache.get(origin), {
          headers: { 'cache-control': 'public, max-age=300, s-maxage=300' },
        })
      },
    },
  },
})
```

**`src/routes/api/docs.ts`** — Scalar via CDN, version-pinned:

```ts
import { createFileRoute } from '@tanstack/react-router'

const html = `<!doctype html>
<html><head><title>API</title><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /></head>
<body>
  <script id="api-reference" data-url="/api/openapi"></script>
  <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.52.6"></script>
</body></html>`

export const Route = createFileRoute('/api/docs')({
  server: {
    handlers: {
      GET: () => new Response(html, {
        headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' },
      }),
    },
  },
})
```

Note: TanStack file routing treats `.` as a path separator, so `/api/openapi.json` is not a valid route name. Use `/api/openapi` and still return JSON.

### 6. Bruno collection (skip if `--no-bruno`)

Structure:

```
bruno/
  bruno.json
  collection.bru            # docs block telling users to pick an env
  environments/
    local.bru               # baseUrl: http://localhost:3000
    production.bru          # baseUrl: <deployed host>
    mock.bru                # baseUrl: http://localhost:4010 (only if mock enabled)
  <folder-per-resource>/
    <method>-<name>.bru     # status + shape assertions per route
```

**`bruno/bruno.json`**:

```json
{ "version": "1", "name": "My API", "type": "collection", "ignore": ["node_modules", ".git"] }
```

**`bruno/environments/local.bru`**:

```
vars {
  baseUrl: http://localhost:3000
}
```

Bruno does not have a built-in `isObject` assertion. For object shape checks, use the `tests { }` block with chai:

```
tests {
  test("body.definitions is an object", () => {
    expect(res.body.definitions).to.be.an("object")
  })
}
```

Bruno also doesn't commit the active environment (tracked in usebruno/bruno#303). Add a `collection.bru` with a `docs { }` block so the first thing a user sees is "pick the local environment."

### 7. Prism mock server (skip if `--no-mock`)

**`scripts/generate-openapi.ts`** — dumps spec to `openapi.json` at repo root:

```ts
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildOpenApiDocument } from '../src/server/openapi'

const doc = buildOpenApiDocument({
  servers: [{ url: 'http://localhost:4010', description: 'Prism mock' }],
})
writeFileSync(resolve(import.meta.dirname, '..', 'openapi.json'), JSON.stringify(doc, null, 2) + '\n')
console.log('Wrote openapi.json')
```

Add `openapi.json` to `.gitignore` (regenerated by `pnpm mock`).

Run Prism **without `--dynamic`** so the schema examples get used instead of faker Lorem ipsum.

### 8. `package.json` scripts

```jsonc
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:e2e": "playwright test",
  "test:visual": "PLAYWRIGHT_VISUAL=1 playwright test e2e/visual.spec.ts",
  "test:visual:update": "PLAYWRIGHT_VISUAL=1 playwright test e2e/visual.spec.ts --update-snapshots",
  "test:integration": "start-server-and-test dev http://localhost:3000 'vitest run --config vitest.integration.config.ts'",
  "test:api": "start-server-and-test dev http://localhost:3000 'cd bruno && bru run . -r --env local'",
  "test:api:prod": "cd bruno && bru run . -r --env production",
  "openapi:dump": "tsx scripts/generate-openapi.ts",
  "mock": "pnpm run openapi:dump && prism mock openapi.json --port 4010"
}
```

### 9. CI jobs (`.github/workflows/ci.yml`)

Three parallel jobs after `quality-checks` (format + lint + build + unit test): `e2e`, `integration`, `api-contract`. All block `deploy`.

```yaml
e2e:
  needs: test
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: pnpm/action-setup@v4
      with: { version: 9 }
    - uses: actions/setup-node@v4
      with: { node-version: 22, cache: pnpm }
    - run: pnpm install --frozen-lockfile
    - run: pnpm exec playwright install --with-deps chromium
    - run: pnpm db:migrate:local # if using D1
    - run: pnpm test:e2e
    - uses: actions/upload-artifact@v4
      if: always()
      with: { name: playwright-report, path: playwright-report/ }

integration:
  needs: test
  # same shape, replace last two steps with `pnpm test:integration`

api-contract:
  needs: test
  # same shape, replace last two steps with `pnpm test:api`

deploy:
  needs: [test, e2e, integration, api-contract]
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

## What NOT to do (anti-patterns baked in)

- **No blanket coverage threshold (80%)**. Ratchet-style is slightly less wrong but still solves a non-problem at solo scale.
- **No `.strict()` on Zod objects by default**. Breaks callers that send extra fields; only earns its keep on externally-consumed APIs.
- **No Redoc alongside Scalar by default**. One doc UI is enough. Add Redoc only if readers are auditing cross-references between many shared schemas.
- **No `x-faker` per-field hints or custom mock handlers**. Schema `example` fields cover it.
- **No shape-only `test:api:mock` Bruno variant**. Real `pnpm test:api` against live is authoritative for solo projects.
- **No blanket examples on every schema**. Only the 2–3 headline response schemas get them. The rest are viewed nested.

## References

- ADR: `connections-helper/docs/adr/0001-testing-and-docs-stack.md`
- Entity pages in `llm-wiki-research`: `openapi`, `scalar`, `redoc`, `prism`, `bruno`
- Comparison: `scalar-vs-redoc` in `llm-wiki-research`

## See also

- `/ro:new-tanstack-app` — orchestrator that invokes this skill
- `/ro:better-auth install` — add auth endpoints (and their Bruno tests)
- `/ro:cf-ship` — deploy to Cloudflare Workers
- `/ro:gh-ship` — push through GitHub PR pipeline
