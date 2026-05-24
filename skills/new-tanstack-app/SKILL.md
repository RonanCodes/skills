---
name: new-tanstack-app
description: Orchestrate scaffolding a new TanStack Start app on the canonical stack (TanStack Start + Drizzle + Neon Postgres + Cloudflare Workers + shadcn/ui). Dispatches to sub-skills for DB (Neon default; D1 via --db sqlite), auth (Clerk by default for small SaaS; WorkOS AuthKit as alt-at-scale for B2B 100K+ MAU; Better Auth as alt for owns-the-table / EU-mandate / custom-flows), observability (PostHog, Sentry, UptimeRobot), DNS, ship; plus optional agentic runtime (XState + Vercel AI SDK, LangGraph Phase-2 POA) and Knock notifications. Use when user wants to start, create, scaffold, bootstrap, or kick off a new TanStack Start project / small app / side project.
category: project-setup
argument-hint: <app-name> [--db sqlite] [--auth] [--posthog] [--sentry] [--uptime] [--agent xstate|langgraph] [--ai-sdk] [--knock] [--domain <host>] [--skip-deploy] [--skip-ci] [--skip-styleguide] [--interactive]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(corepack *) Bash(mkdir *) Bash(cd *) Bash(cp *) Read Write Edit
---

# New TanStack App (orchestrator)

Scaffold a new TanStack Start app, then dispatch to sub-skills for the pieces the user wants. Target: $0/mo at small scale, one evening to a working deploy.

## Usage

```
/ro:new-tanstack-app my-app                              # baseline: Neon Postgres, no auth, no observability, deploy
/ro:new-tanstack-app my-app --interactive                # asks what to wire (uses AskUserQuestion)
/ro:new-tanstack-app my-app --db sqlite                  # D1 (SQLite) instead of Neon, for edge-cache / CLI shapes
/ro:new-tanstack-app my-app --auth                       # + Clerk (default); --auth=workos for B2B-at-scale; --auth=better-auth for the owns-the-table alt
/ro:new-tanstack-app my-app --posthog --sentry --uptime  # + full observability
/ro:new-tanstack-app my-app --agent xstate --ai-sdk      # + XState decision machine + Vercel AI SDK (Anthropic/OpenAI/Gemini)
/ro:new-tanstack-app my-app --knock                      # + Knock (multi-channel notifications: Slack + email + in-app)
/ro:new-tanstack-app my-app --domain api.ronan.dev       # + custom domain via /ro:cloudflare-dns
/ro:new-tanstack-app my-app --skip-deploy                # scaffold only, no deploy
/ro:new-tanstack-app my-app --auth --agent xstate --ai-sdk --knock --posthog --sentry --uptime --domain app.ronan.dev  # full agentic app
```

## What it actually does

This skill is an **orchestrator** — it owns the baseline scaffolding (scaffold / UI / testing / hygiene) and delegates everything else to sibling skills. That keeps each piece evolvable on its own.

```
/ro:new-tanstack-app <app> [flags]
  1. scaffold + CF adapter + wrangler binding            (inline)
  2. DB wiring:
       default (Neon)    → /ro:neon install + project + push-secret
       --db sqlite        → inline D1 wiring
  3. UI: tailwind + shadcn + lucide                       (inline)
  4. Testing + API docs                → /ro:testing-stack install
  5. Code hygiene: prettier + eslint + husky + commitlint (inline)
  6. --auth              → /ro:clerk install (default); --auth=workos → /ro:workos install (B2B at 100K+ MAU); --auth=better-auth → /ro:better-auth install (owns-the-table / EU-mandate / custom-flows)
  6a. Design system + /styleguide route → /ro:design-system-create --showcase (default-on; consumes requireRole() if --auth, dev-only fallback otherwise)
  7. --ai-sdk            → install `ai` + `@ai-sdk/anthropic` + `@ai-sdk/openai` + `@ai-sdk/google`; scaffold `lib/models.ts`
  8. --agent xstate      → install `xstate` + `@xstate/react`; scaffold a reference `machines/exampleMachine.ts` + actor using AI SDK
  8b. --agent langgraph  → Phase-2 POA (not yet auto-scaffolded) — prints migration POA instead
  9. --knock             → install `@knocklabs/node` + `@knocklabs/react`; scaffold `/api/notify` route stub
 10. --posthog   → /ro:posthog install --both
 11. --sentry    → /ro:sentry install --tanstack + project create
 12. --uptime    → /ro:uptimerobot monitor create          (post-deploy)
 13. --domain    → /ro:cloudflare-dns add <host>           (post-deploy)
 14. deploy      → /ro:cf-ship                             (unless --skip-deploy)
 15. GitHub CI  → add .github/workflows/ci.yml            (quality gate + auto-deploy)
 15a. GitHub branch protection + squash-only merges (see /ro:stacked-prs for the rebase flow)
 16. final commit → /ro:commit                             (emoji format)
```

## Prerequisites

- Node 20+
- `pnpm` (install: `corepack enable pnpm`)
- `wrangler` 4.x — `pnpm add -g wrangler` (skill checks and offers to install)
- `CLOUDFLARE_API_TOKEN` in `~/.claude/.env` with Workers Scripts + Account Settings + Zone DNS scopes
- `NEON_API_KEY` in `~/.claude/.env` (required for the default Neon DB path; create at console.neon.tech)
- Git configured
- For optional flags, the corresponding env vars must be set (skill checks):
  - `--db sqlite` → no extra env var needed (D1 is managed via wrangler)
  - `--posthog` → `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_HOST`, `POSTHOG_INGEST_HOST`
  - `--sentry` → `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_REGION_URL`
  - `--uptime` → `UPTIMEROBOT_API_KEY`
  - `--ai-sdk` → at least one of `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY` (pushed to Worker as a secret, not `~/.claude/.env`-only)
  - `--knock` → `KNOCK_API_KEY` (pushed as a Worker secret)
  - `--domain` → `CLOUDFLARE_API_TOKEN` with `Zone:DNS:Edit`

## Interactive mode (`--interactive`)

Runs an `AskUserQuestion` preamble to collect:

1. **Database** — Neon Postgres (default) or D1 SQLite (use `--db sqlite` for edge-cache / CLI shapes)?
2. **Auth**: Cloudflare Access + WARP (recommended for single-user / internal / personal apps, edge-gated, phishing-resistant, no in-app login), Clerk (default for multi-user small SaaS, enable passkeys), WorkOS (alt-at-scale: 100K+ MAU, Admin Portal, SAML SSO), Better Auth (alt for owns-the-table / EU mandate / custom flows), or none? In all cases offer passkeys; see the authentication-hardening playbook.
3. **Agent runtime** — None / XState (MVP: prescriptive decision machine) / LangGraph POA (Phase 2 migration notes only)?
4. **LLM provider abstraction** — Install Vercel AI SDK + provider packs?
5. **Notifications** — Knock (multi-channel) / Resend-only / none?
6. **Observability** — Which of [PostHog, Sentry, UptimeRobot]?
7. **Custom domain** — `<host>` or skip?
8. **Deploy now** — yes (via `/ro:cf-ship`) or scaffold-only?

Answers are converted to flags and the non-interactive flow proceeds. Use this as the default when a user invokes without flags AND without `--skip-interactive`.

## Process

### 1. Baseline scaffold (always)

```bash
pnpm create tsrouter-app@latest <app-name> --template start
cd <app-name>
pnpm install
git init && git add -A && git commit -m "🧹 chore: scaffold tanstack start"
```

### 1a. Supply-chain hardening (always) → `/ro:harden-npm`

Run **immediately after the first `pnpm install`**, before any other step adds packages. This locks in pnpm 11 defaults (`minimumReleaseAge=1440`, `strictDepBuilds=true`, `blockExoticSubdeps=true`), pins `packageManager` in `package.json`, writes a per-repo `.npmrc` with the same settings as defence-in-depth, and runs `pnpm approve-builds` to set the `pnpm.onlyBuiltDependencies` allowlist.

```bash
/ro:harden-npm
```

If pnpm < 11 on the host machine, the skill auto-upgrades via corepack before applying. Idempotent — safe to re-run after later `pnpm add` calls.

Background: triggered by Mini Shai-Hulud v2 (CVE-2026-45321) supply-chain attack on TanStack. Full context in `llm-wiki-security/wiki/incidents/mini-shai-hulud-v2-tanstack.md`.

### 2. Wire Cloudflare adapter (always)

```bash
pnpm add -D @cloudflare/workers-types wrangler
```

Set `app.config.ts` → `preset: 'cloudflare-module'`. Create `wrangler.toml` with app name + compatibility date.

### 3. Database — dispatch

Default DB is **Neon Postgres**. Use `--db sqlite` to opt into D1 instead. The canonical pick for SaaS-shape apps is Neon: standard Postgres at any scale, no migration-count API-rate-limit risk, and the HTTP driver works in Cloudflare Workers without TCP sockets. See the db-pick-decision-rule in [llm-wiki](https://github.com/RonanCodes/llm-wiki) for when to deviate.

- **Neon (default)**: `/ro:neon install` wires Drizzle + `@neondatabase/serverless` with `drizzle-orm/neon-http`. Then `/ro:neon project create <app-name>` and `/ro:neon push-secret` to write `NEON_DATABASE_URL` as a wrangler secret. Template files at `skills/new-tanstack-app/templates/src/db/neon.ts`, `drizzle/neon/`, and `drizzle/neon/drizzle.config.ts` are copied into the new app. Post-scaffold: create a Neon project at [console.neon.tech](https://console.neon.tech), copy the connection URI, run `wrangler secret put NEON_DATABASE_URL --env production`.
- **`--db sqlite`**: inline D1 wiring. Add `[[d1_databases]]` binding in `wrangler.toml`, then `wrangler d1 create <app-name>_db`, patch `database_id`. Install `drizzle-orm` + `drizzle-kit` with `dialect: 'sqlite'`, `driver: 'd1-http'`. Use this for edge-cache, CLI tools, or apps that truly need SQLite semantics.

Either way, create `src/db/schema.ts` (Neon: `pgTable`, D1: `sqliteTable`) with a minimal example table.

### 4. UI stack (always)

```bash
pnpm add -D tailwindcss @tailwindcss/vite
pnpm add lucide-react
pnpm dlx shadcn@latest init
pnpm dlx shadcn@latest add button dialog input form
```

Add `@tailwindcss/vite` plugin. Add `@import "tailwindcss";` to the root CSS.

### 5. Testing + API docs stack (always) → `/ro:testing-stack install`

Delegate to `/ro:testing-stack install`. That sub-skill scaffolds the full seven-layer pattern:

1. Vitest unit tests
2. Vitest integration tests against real upstreams
3. Playwright e2e (Chromium, with visual-regression opt-in)
4. Bruno API collection with `local` / `production` / `mock` environments
5. Zod + `@asteasolutions/zod-to-openapi` served at `/api/openapi`, Scalar docs at `/api/docs`
6. Prism mock server on :4010 via `pnpm mock`
7. k6 ad-hoc load tests (`scripts/loadtest.js` + `pnpm loadtest:smoke|local|prod|burst`); requires one-time `brew install k6`. Not in CI by default.

Plus `package.json` scripts, three CI jobs (`e2e`, `integration`, `api-contract`) gating deploy, and documented anti-patterns (no blanket coverage, no global `.strict()`, no Redoc, no `x-faker`).

Reference: `connections-helper/docs/adr/0001-testing-and-docs-stack.md`.

### 6. Code hygiene (always)

```bash
pnpm add -D prettier eslint typescript \
  @typescript-eslint/parser @typescript-eslint/eslint-plugin \
  eslint-config-prettier prettier-plugin-tailwindcss \
  husky lint-staged \
  @commitlint/cli
pnpm exec husky init
```

- `.prettierrc.json`, flat `eslint.config.js` with `strictTypeChecked` + `prettier` last.
- `tsconfig.json` strict (`strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`).
- `package.json` scripts:
  - `"format": "prettier --check ."` (CI gate).
  - `"format:write": "prettier --write ."` (one-shot baseline, run once after scaffolding to set the repo-wide baseline).
  - `"prepare": "husky"` (bootstraps hooks on every `pnpm install`).
- `lint-staged` block in `package.json` that runs `prettier --write` on the usual source globs.
- `.husky/pre-commit` → `pnpm exec lint-staged` (auto-format staged files before every commit: eliminates the class of "CI fails on formatting" PRs).
- `.husky/commit-msg` → `pnpm exec commitlint --edit "$1"`.
- `.husky/pre-push` → `pnpm quality-checks` (format + lint + build + test + audit). Bypassable with `SKIP_QUALITY_CHECKS=1 git push --no-verify` for real emergencies. **This hook is the load-bearing piece that lets `/ro:planner-worker` and `/ro:ralph` default to `--trust-local-ci` for this repo: a successful push means CI has effectively passed locally, so workers squash-merge immediately instead of waiting 1-2 min per PR for GitHub Actions to re-run the same gauntlet.** See `/ro:planner-worker` § "Lessons from live runs" lesson #5 for the policy.
- `commitlint.config.mjs` enforcing the **emoji + conventional** format from `CLAUDE.md` (✨ feat / 🐛 fix / 🧪 test / 📝 docs / 🧹 chore / ♻️ refactor / 🚀 deploy / 🔧 config / ⚡ perf / 🔒 security). Use a custom parser-preset + two rules (`emoji-allowed`, `emoji-type-matches`). Do **not** use `@commitlint/config-conventional`: it doesn't know about the emoji requirement, so it'd half-enforce the convention. Copy the config verbatim from `connections-helper/commitlint.config.mjs`.

After scaffolding, run `pnpm format:write` once to set the baseline so subsequent pre-commit hooks have nothing to change on untouched files.

Reference: `connections-helper/docs/adr/0002-github-branch-protection-squash-only-merges.md`.

### 7. `--auth` → `/ro:clerk install` (default), `/ro:workos install` (alt-at-scale), or `/ro:better-auth install` (alt-optionality)

**Security canon (applies to every auth path).** Auth is the main attack surface once data is encrypted, so make it secure by default, per the `authentication-hardening` playbook (`llm-wiki-security/wiki/playbooks/authentication-hardening.md`):

- **Always offer a phishing-resistant factor (passkey / FIDO2 / WebAuthn).** It's the NIST 800-63B AAL2+ and CISA gold standard; SMS/TOTP are phishable. Whichever provider is chosen below, enable passkeys and don't ship SMS-only MFA.
- **Single-user / internal / personal apps: prefer gating at the edge** with **Cloudflare Access + WARP device posture** instead of a public login form, the app stays unreachable to the internet and the attack surface collapses to "CF edge + IdP". (This is the Tailscale-equivalent on Workers; Tailscale itself only gates self-hosted boxes.) For these, auth may need no in-app provider at all, just Access + a JWT-verify in the Worker. Surface this as the recommended option when the app is described as "just me" / internal / personal.
- **Short sessions + step-up re-auth** before sensitive actions; auth/signing secrets in a secret store.

Default (multi-user / public SaaS): delegate to `/ro:clerk install`. Clerk (hosted UI components, free to 10K MAU, fastest first sign-in) is the canonical pick for small SaaS where speed-to-market matters; enable passkeys in the Clerk dashboard.

Flip to `/ro:workos install` when any of these is true:
- MAU is expected to cross 100K within 12 months (Clerk's per-MAU cost ramps; WorkOS is free to 1M MAU).
- A non-engineer partner needs the WorkOS Admin Portal for user-management visibility.
- Enterprise SSO via per-connection SAML is on the near-term roadmap.

Trigger via `--auth=workos` flag, or via the interactive picker (Question 2) above.

Flip to `/ro:better-auth install` when any of these is true:
- User must own the `users` table for native joins / FKs / row-level security against domain data.
- EU data-residency mandate that neither Clerk nor vendored AuthKit can satisfy on their standard plans.
- Fully custom auth flows (unusual onboarding, custom session shape, exotic providers).
- Zero vendor lock-in is a hard preference (Auth.js consolidation under the Better Auth team in 2026 makes this the safest principled-OSS pick).

Trigger via `--auth=better-auth` flag, or via the interactive picker (Question 2) above.

Afterwards (Clerk path):
- Remind user: `CLERK_SECRET_KEY`, `CLERK_PUBLISHABLE_KEY`, `CLERK_WEBHOOK_SECRET` live in `.dev.vars` + `wrangler secret put`, NOT in `~/.claude/.env`. The publishable key ships to the browser bundle (safe).

Afterwards (WorkOS path):
- Remind user: `WORKOS_API_KEY`, `WORKOS_CLIENT_ID`, `WORKOS_COOKIE_PASSWORD`, `WORKOS_REDIRECT_URI` live in `.dev.vars` + `wrangler secret put`, NOT in `~/.claude/.env`.

Afterwards (Better Auth path):
- Remind user: `BETTER_AUTH_SECRET` generated via `openssl rand -base64 32` lives in `.dev.vars` + `wrangler secret put`, NOT in `~/.claude/.env`.

### 6a. Design system + `/styleguide` route (always, unless `--skip-styleguide`)

Delegate to `/ro:design-system-create --showcase`. Runs **after** auth so the role helper (`src/lib/auth/roles.ts`) emitted by `/ro:clerk install` is on disk by the time the styleguide route gets wired.

What you get:

- `src/design-system/tokens.ts` — typed TYPOGRAPHY, SPACING, RADIUS, ELEVATION, Z
- `DESIGN_SYSTEM.md` at repo root — rules + state tables + review checklist
- cva-based variants on the shadcn primitives (Button, Input, Card)
- `src/routes/styleguide.tsx` — the role-gated showcase page:
  - **With `--auth`:** gated via `requireRole('superadmin', 'staff')`. Returns 404 to anyone else. Superadmin email is hardcoded (`admin@simplicitylabs.io` by default — edit `SUPERADMIN_EMAILS` in `src/lib/auth/roles.ts` per app). Staff = Clerk org members with the custom `org:staff` role (one-time dashboard setup, see `/ro:clerk` § add-roles).
  - **Without `--auth`:** dev-only fallback. The route renders in `pnpm dev` and 404s in production builds.

Skip with `--skip-styleguide` if (and only if) the user explicitly doesn't want it. Default is on because the styleguide is the cheapest design-system audit surface and the natural landing pad for any future admin panel.

Mention to the user post-scaffold: once they create the first Clerk org and want a teammate (e.g. Taskforce employee) to view `/styleguide` on production, promote them to `org:staff` in the Clerk dashboard. No deploy needed.

### 7a. `--ai-sdk` → Vercel AI SDK (provider abstraction)

```bash
pnpm add ai @ai-sdk/anthropic @ai-sdk/openai @ai-sdk/google zod
```

Scaffold `src/lib/models.ts`:

```ts
import { anthropic } from "@ai-sdk/anthropic";
import { openai } from "@ai-sdk/openai";
import { google } from "@ai-sdk/google";

export const models = {
  primary: anthropic("claude-opus-4-7"),
  fast: anthropic("claude-haiku-4-5-20251001"),
  alternate: openai("gpt-5"),
  cheap: google("gemini-2.5-flash"),
} as const;
```

Scaffold `src/routes/api/chat.ts` as a reference `streamText` endpoint using `toDataStreamResponse()`. Prompt-caching breakpoints via `providerOptions: { anthropic: { cacheControl: { type: "ephemeral" } } }`. Document in `ARCHITECTURE.md` that provider swap = change one import in `lib/models.ts`.

**For downstream feature work, point the user (and future agents) at `/ro:vercel-ai-sdk`.** It covers every Core primitive (`streamText`, `generateText`, `generateObject`, `streamObject`, `embed`, tool() agentic loops, `wrapLanguageModel` middleware), every UI hook (`useChat`, `useCompletion`, `useObject`), the v6 `UIMessage` parts[] wire protocol, provider-specific tricks (Anthropic prompt caching + extended thinking, OpenAI reasoning effort + structured outputs, Google grounding), edge-runtime gotchas, and v5→v6 migration. **Append this line to the scaffolded `AGENTS.md` and `CLAUDE.md`:**

```markdown
## AI SDK

This project uses the Vercel AI SDK (v6). For patterns, primitives, recipes, and provider-specific tricks, load `/ro:vercel-ai-sdk` before adding or modifying any AI feature.
```

That cross-reference is what auto-loads the AI-SDK skill the next time someone asks for a chat / streaming / structured-output / tool-calling feature in this project.

Push provider keys as Worker secrets: `wrangler secret put ANTHROPIC_API_KEY` (and/or OPENAI/GOOGLE).

### 7b. `--agent xstate` → XState decision machine

```bash
pnpm add xstate @xstate/react
```

Scaffold `src/machines/exampleMachine.ts` — a prescriptive state machine with one `fromPromise` actor calling `generateObject` (if `--ai-sdk` also set) for typed classification. Scaffold `src/components/Machine.tsx` using `useMachine`. Wire a reference route `src/routes/machine.tsx`.

If `--auth` is also set, the example machine reads `client_id` from `auth.api.getActiveMember()` and passes it in machine context for future RLS-scoped tool calls.

### 7c. `--agent langgraph` → Phase-2 POA (no auto-scaffold)

Don't install LangGraph today on Cloudflare Workers — the stock `@langchain/langgraph-checkpoint-postgres` uses `pg` TCP and will not run. Instead print a migration POA to stdout covering:

- Use XState at the top level; invoke a LangGraph workflow from an XState actor when a sub-tree needs free-form agentic planning.
- Checkpointer options on Workers: D1 adapter, Neon-HTTP custom checkpointer, or Durable Object per-session storage (preferred).
- Add LangSmith (`LANGSMITH_API_KEY`) when the first LangGraph workflow ships; before that, Sentry + PostHog telemetry is sufficient.

### 7d. `--knock` → Knock notifications (multi-channel)

```bash
pnpm add @knocklabs/node @knocklabs/react
```

Scaffold `src/routes/api/notify.ts`:

```ts
import { Knock } from "@knocklabs/node";
export const APIRoute = createAPIFileRoute("/api/notify")({
  POST: async ({ request }) => {
    const knock = new Knock(env.KNOCK_API_KEY);
    const { workflow, recipients, data } = await request.json();
    await knock.workflows.trigger(workflow, { recipients, data });
    return new Response(null, { status: 204 });
  },
});
```

Push `wrangler secret put KNOCK_API_KEY`. Document expected workflow IDs in `ARCHITECTURE.md` so product/design can create them in Knock's UI.

Note: Resend for transactional email is still installed via the baseline scaffold when `--knock` is set alongside — Knock can delegate the email channel to Resend.

### 8. `--posthog` → /ro:posthog install --both

Delegate. Client + server SDK. For public-facing apps, prefer **runtime config injection** over `VITE_*` (see "Runtime-injected observability" below) — the key still ships to browsers either way, but runtime injection means forks don't ship your key and rotations don't need a rebuild.

### 9. `--sentry` → `/ro:sentry install --tanstack` + `project create`

Delegate install. Then `/ro:sentry project create <app-slug> --platform javascript-react` creates a Sentry project and returns the DSN. For public-facing apps, prefer **runtime config injection** (see below) over `VITE_SENTRY_DSN`.

### Runtime-injected observability (recommended default)

Instead of baking Sentry DSN + PostHog key into the bundle via `VITE_*` vars, store them as Cloudflare Worker `vars` and expose them via an `/api/config` endpoint the client fetches on load. Scaffold:

- `wrangler.jsonc` → `vars: { SENTRY_DSN: "", POSTHOG_PROJECT_KEY: "", POSTHOG_INGEST_HOST: "https://eu.i.posthog.com" }`
- `src/routes/api/config.ts` → GET returns `{ sentryDsn, posthogKey, posthogHost }` from `env`
- `src/lib/runtime-config.ts` → memoised client-side `fetch('/api/config')`
- `initSentry()` / `initPostHog()` are **async**, read from runtime-config, no-op if keys are empty

Benefits: keys rotate without rebuilds, CI builds without observability secrets, forks don't ship your keys. Cost: one extra fetch before analytics init (fine for non-critical-path analytics). Document the flow in `ARCHITECTURE.md`.

### 10. `--uptime` → `/ro:uptimerobot monitor create` (post-deploy)

Deferred to post-deploy — needs the Worker URL first. After `/ro:cf-ship` prints the URL:

```
/ro:uptimerobot monitor create <worker-url> --name "<app-name>"
```

### 11. `--domain <host>` → `/ro:cloudflare-dns` (post-deploy)

Deferred to post-deploy. After the Worker is live:
- Add custom domain binding via `wrangler.toml` → `routes` or `wrangler custom-domains add`
- `/ro:cloudflare-dns add <host>` adds a CNAME to the Worker (proxied/orange-cloud)

### 12. Deploy — `/ro:cf-ship` (always, unless `--skip-deploy`)

Run `/ro:cf-ship` for the full pre-flight gate: typecheck, lint, format, test, D1 migrations, secrets diff, build, deploy, smoke check. This replaces the inline `wrangler deploy` from the old version of this skill — the pre-flight gate is a big value-add and shouldn't be duplicated.

### 13. GitHub CI + auto-deploy (always, unless `--skip-ci`)

Every app ships with CI from day one. Two jobs: a `test` job that runs on every push and PR (format + lint + build + test, collapsed into a single `pnpm quality` script), and a `deploy` job that runs only on push to main, gated on `test`, deploying to Cloudflare with secrets from the `production` environment.

**HARD RULES for the deploy workflow:**

1. **Neon migrations (default):** `pnpm db:migrate` (runs `drizzle-kit migrate --config drizzle/neon/drizzle.config.ts`) before the wrangler deploy step. Reads `NEON_DATABASE_URL` from the `production` environment secret. Drizzle applies only unapplied migrations tracked in `drizzle/neon/meta/_journal.json`.
2. **D1 migrations (`--db sqlite` only):** `wrangler d1 migrations apply <db-name> --remote`. NEVER a `for f in drizzle/*.sql; do wrangler d1 execute --file=$f` loop. Drizzle's `meta/_journal.json` + the remote `d1_migrations` tracking table are how D1 knows what's already applied. The brute-force loop runs every file every deploy and trips CF Workers API rate-limit 10429 on repos with active merge cadence. Real incident: lekkertaal 2026-05-19 (PR `RonanCodes/lekkertaal#169` was the cleanup). See [[canon:d1-migrations]].
3. **`paths-ignore` on `push`:** docs-only / retro / chore-artefact pushes should NOT trigger deploys. Filter at least `**/*.md`, `docs/**`, `.nightshift/**`, `.ralph/**`, `.completion-reports/**`. PRs still run the full workflow regardless of paths so reviewers see CI status.
4. **Use `cloudflare/wrangler-action@v3`** rather than raw `pnpm wrangler` shell calls. The action handles auth + retry + output formatting better and is the canonical pattern (matches dataforce, lekkertaal post-#169, factory).

Create `.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
    # docs / retro / chore-artefact pushes must NOT trigger deploys, see HARD RULE 2 above
    paths-ignore:
      - "**/*.md"
      - "docs/**"
      - ".nightshift/**"
      - ".ralph/**"
      - ".completion-reports/**"
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  test:
    name: Quality checks (format + lint + build + test)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm quality
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
      # Apply only new Neon migrations. drizzle-kit reads drizzle/neon/meta/_journal.json
      # and applies only migration files that haven't run yet.
      # NEON_DATABASE_URL must be set in the production environment secret.
      - name: Apply Neon migrations
        env:
          NEON_DATABASE_URL: ${{ secrets.NEON_DATABASE_URL }}
        run: pnpm db:migrate
      - name: Deploy worker
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: deploy
```

If `--posthog` / `--sentry` are set, add `--var` flags to the `wrangler deploy` step (reading from `secrets.SENTRY_DSN` and `secrets.POSTHOG_PROJECT_KEY`), matching the runtime-config pattern from step 8-9.

Add a collapsing `quality` script to `package.json` so local + CI share one command:

```json
"scripts": {
  "quality": "pnpm run format && pnpm run lint && pnpm run build && pnpm run test"
}
```

Push secrets to the `production` environment.

**Gotcha — `GITHUB_TOKEN` in `~/.claude/.env` shadows gh's keychain auth.** If the script sources `~/.claude/.env` to read `CLOUDFLARE_API_TOKEN` (etc.), `GITHUB_TOKEN` from that file takes priority over the keychain-stored gh token, and `gh secret set` fails with `HTTP 401: Bad credentials` on the public-key endpoint — even though `gh api` works on the same URL. Fix: `unset GITHUB_TOKEN GH_TOKEN` right after sourcing, before any gh call.

Needs a `gh` token with `repo` scope and admin on the environment — if it 401s despite the unset, run `gh auth refresh -h github.com -s admin:repo_hook` and pass `--repo <owner>/<name>` explicitly:

```bash
set -a && source "$(ro context env)" && set +a
unset GITHUB_TOKEN GH_TOKEN   # required — see gotcha above
REPO=<owner>/<repo>

gh secret set CLOUDFLARE_API_TOKEN --env production --repo $REPO --body "$CLOUDFLARE_API_TOKEN"
gh secret set CLOUDFLARE_ACCOUNT_ID --env production --repo $REPO --body "$CLOUDFLARE_ACCOUNT_ID"
gh secret set NEON_DATABASE_URL --env production --repo $REPO --body "$NEON_DATABASE_URL"
# observability (if wired):
gh secret set SENTRY_DSN --env production --repo $REPO --body "$SENTRY_DSN"
gh secret set POSTHOG_PROJECT_KEY --env production --repo $REPO --body "$POSTHOG_PROJECT_KEY"
```

Why `environment: production` and not repo-level secrets: preview branches / PRs never see the deploy token. Required status checks can gate deploys per-environment. Audit log shows which env a secret was used in.

Skip with `--skip-ci` if (and only if) the user explicitly doesn't want CI. Default is on.

### 13a. GitHub branch protection + squash-only merges (always, unless `--skip-ci`)

After CI is wired and the first push lands so GitHub knows the check contexts exist, lock `main` down. Two API calls, both idempotent.

**1. Branch protection on `main`:**

```bash
REPO=<owner>/<repo>
gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Quality checks (format + lint + build + test)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
```

Extend the `contexts` list with every CI job name that should gate merging. The job **name** is what appears (look at `gh pr checks <PR>` output), not the workflow name. If `/ro:testing-stack` is wired, add: `Playwright e2e`, `Integration tests (real external APIs)`, `API contract (Bruno)`, `Playwright visual diff`, `Accessibility + performance budget`, `Secret scan (gitleaks + trufflehog)`, `Dependency audit (pnpm)`. Do **not** include the deploy job: it only runs on push to main, never on PRs, and would permanently block merges.

**2. Repo-level squash-only merge settings:**

```bash
gh api -X PATCH "repos/$REPO" \
  -f allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY
```

Why these settings, including the research backing squash-only: `connections-helper/docs/adr/0002-github-branch-protection-squash-only-merges.md`. tl;dr: 14 of 18 surveyed TS/JS flagship projects (TypeScript, Next.js, React, Vite, Astro, Svelte, tRPC, Prettier, ESLint, Playwright, TanStack Query, Tailwind, Vue core, Hono) use squash-only on main. The outliers are the less disciplined ones.

**Stacked-PR workflow:** once protection is on, stacked PRs need rebase-after-parent-merges. Codified in `/ro:stacked-prs`.

### 14. Final commit — `/ro:commit`

Delegate to `/ro:commit` so the emoji format and weekday-timestamp rule are enforced.

## Output summary

Print the following after everything runs:

- App name + directory
- DB: Neon project ID + branch (connection URI set as wrangler secret), OR D1 database ID (if `--db sqlite`)
- Auth: enabled / disabled (Clerk / WorkOS / Better Auth)
- Design system: tokens + DESIGN_SYSTEM.md emitted, `/styleguide` route at gate=`requireRole(superadmin,staff)` / `dev-only`
- Agent runtime: XState (scaffolded reference machine) / LangGraph POA printed / none
- LLM provider abstraction: Vercel AI SDK installed + configured providers
- Notifications: Knock workspace wired / Resend-only / none
- Observability wired: PostHog flag, Sentry project slug + DSN source, UptimeRobot monitor ID
- Deployed URL + custom domain (if `--domain`)
- Next-step suggestions: add more shadcn components, write first Server Function, `pnpm dev`

## Safety

- Every sub-skill has its own safety rules — this orchestrator does not override them.
- If a sub-skill's required env var is missing, skill fails fast at the top with "Missing: X. Add to `~/.claude/.env`" — does NOT attempt partial setup.
- `--skip-deploy` implies `--uptime` and `--domain` are also skipped (they're post-deploy).
- If `wrangler whoami` shows an insufficient-scope token, skill fails fast before any `wrangler deploy` call.
- If `NEON_DATABASE_URL` is absent at runtime, `getNeonClient` throws a clear error with setup instructions rather than passing an empty string to the Neon driver.

## Anti-patterns it guards against

- Inlining sub-skill logic here (drifts from the sub-skill's source of truth)
- Silently continuing when a sub-skill fails (bad state + partial deploy)
- Assuming a token has full Workers scope without verifying
- Using TCP drivers for Postgres inside Workers (Neon HTTP driver only — enforced by `/ro:neon`)
- Defaulting new SaaS apps to D1: D1 is SQLite-on-edge, not Postgres. Migration-count API rate limits (CF 10429) hit active repos at ~100 migrations. Use D1 only via explicit `--db sqlite` for edge-cache / CLI shapes where SQLite semantics are the right fit.

## See also

- `/ro:migrate-to-tanstack` — port an existing app to this stack (the migration sibling)
- `/ro:neon` — Postgres wiring
- `/ro:clerk` (default auth), `/ro:workos` (alt-at-scale auth), `/ro:better-auth` (alt for owns-the-table cases), `/ro:posthog`, `/ro:sentry`, `/ro:uptimerobot`, `/ro:cloudflare-dns`
- `/ro:setup-logging` — wire the diagnosable-by-default observability baseline (logtape structured logging that EMITS, request context with trace_id/userId/orgId, trace_id FE→BE, CF `observability.enabled`). Run it during scaffold so the app is debuggable from day one; pairs with `/ro:diagnose`.
- **`canon/auth-guards.md` (MANDATORY when the app has auth)** — every login-gated page MUST have a server-side `beforeLoad` guard that redirects signed-out users to sign-in; a signed-out visitor must never render a gated page. Classify every route gated/public + run the audit grep. (Lesson: dataforce shipped a guard pass that missed onboarding + install routes → broken/500 pages for signed-out users.)
- `/ro:design-system-create` — emits `/styleguide` showcase route + DESIGN_SYSTEM.md spec + cva variants (invoked by step 6a)
- `/ro:cf-ship` — the deploy pipeline
- `/ro:commit` — emoji conventional commits
