---
name: infra-docs
description: Generate (and refresh) architect-grade living documentation of an app's deployed cloud infrastructure. Discovers the real, live resources (not just what's in config) — Cloudflare Workers + D1 + R2 + Secrets Store + Workers AI + Durable Objects + Zero Trust/Access + cron, or Fly/Vercel equivalents — reads the codebase to map data flows, and writes a multi-document set under docs/infrastructure/ with C4-style architecture diagrams, per-resource detail, mermaid sequence diagrams for every key flow, the security/encryption model, and a from-scratch provisioning runbook. Idempotent: re-run anytime. Designed as a POST-FIRST-DEPLOYMENT step (run it once the app is live) and re-run periodically after deploys/updates. Use when the user says "document the infrastructure", "architecture docs", "document the cloud setup", "what's deployed", "infra docs", or right after a first successful deploy.
allowed-tools: Bash Read Glob Grep Write Edit WebFetch
---

# Infrastructure docs (living architecture documentation)

Produce the documentation a new architect joining the project would want on day one: what cloud resources exist, why each one, how data and auth flow between them, where the security boundaries are, and how to rebuild it from nothing. The point is **understanding**, not an inventory dump.

Two hard rules:

1. **Document the LIVE infrastructure, not just the config.** Read `wrangler.jsonc`/`fly.toml`/`vercel.json` for intent, then query the provider (wrangler / CF API / flyctl) for what is *actually* deployed: resource IDs, regions, table counts, sizes, deployment versions, routes, Access apps. Config drifts from reality; the doc must reflect reality and flag drift.
2. **Never write secret VALUES.** Resource IDs, store IDs, AUD tags, bucket names, account IDs are fine (they're identifiers, not credentials). API tokens, KEKs, signing keys, connection strings with passwords are NEVER written to the docs. If you find one in config, redact it and note where the real value lives (Secrets Store / `wrangler secret` / env).

## When this runs

- **Post-first-deployment (primary trigger).** The moment an app is confirmed live and working (e.g. the tail of `/ro:cf-ship`, `/ro:gh-ship`, `/ro:fly-deploy`), run this to capture the freshly-stood-up infrastructure while it's fresh. This should be a standing step of standing up any new app.
- **Periodic refresh.** After later deploys that change bindings, add resources, or change the auth/security posture. The skill is idempotent: it regenerates the generated sections and preserves any hand-authored `<!-- HAND-EDITED -->` blocks.

## Steps

### 1. Detect the platform and gather config intent

```bash
ls wrangler.jsonc wrangler.toml fly.toml vercel.json 2>/dev/null
```

- **Cloudflare Workers** (`wrangler.*`): the main case. Note `name`, `main`, `compatibility_date`, `triggers.crons`, `vars`, and every binding block (`d1_databases`, `r2_buckets`, `kv_namespaces`, `secrets_store_secrets`, `durable_objects`, `ai`, `queues`, `services`, `hyperdrive`, `vectorize`).
- **Fly** (`fly.toml`): apps, machines, volumes, Postgres, secrets.
- **Vercel** (`vercel.json` / project): functions, env, integrations.

### 2. Query the LIVE provider state

Cloudflare (use the deploy token from `~/.claude/.env` or the project's configured token; `export CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=...`):

```bash
pnpm exec wrangler deployments list                 # current version, history
pnpm exec wrangler d1 list                           # databases
curl .../accounts/$ACC/d1/database/$ID                # region, num_tables, file_size
pnpm exec wrangler r2 bucket list                    # buckets
pnpm exec wrangler secrets-store store list --remote # secret stores (NOT values)
curl .../accounts/$ACC/access/apps                    # Zero Trust / Access apps + policies
curl .../accounts/$ACC/workers/subdomain              # workers.dev hostname
# routes / custom domains, queues, DO classes as applicable
```

Record IDs, regions, sizes, the deployed version hash, the live hostname(s), and the Access AUD/team domain. Note any binding present in config but missing live (or vice versa) as **drift**.

### 3. Read the code to map data flows

Find the real flows, don't invent them:

- Worker entry (`main`): the `fetch` handler, `scheduled` handler (cron), middleware (auth/JWT), DO classes.
- Server functions / route handlers: which binding each one touches (DB read/write, R2 put/get, AI.run, secret .get).
- Cross-cutting: encryption (where encrypt/decrypt happen), auth (where the JWT is verified, step-up gates), the cron job's work.

Identify the 4-8 flows worth a sequence diagram (typical: user-auth/login, primary write path, primary read path, any background/cron job, any AI/model call, any file-upload path, any payment/webhook path).

### 4. Write the document set under `docs/infrastructure/`

Create these (merge/skip per what the app actually has). Lead each with a one-line "generated by /ro:infra-docs on <date>, reflects live state" note.

- **`README.md`** — the entry point. A C4-style **System Context** + **Container** diagram (mermaid `flowchart`), a one-paragraph "what this app is", and a **resource inventory table** (resource | id | region | purpose | limits/tier). Link to the other docs.
- **`resources.md`** — one section per cloud resource. For each: what it is, why it's used (the decision), its live ID/name/region, its config, relevant limits + cost tier, and how to inspect it (the exact `wrangler`/`curl` command). This is the "what exists and why" reference.
- **`data-flows.md`** — a mermaid **sequence diagram** per key flow from step 3, each with a prose walkthrough naming the participants (browser, edge/Access, Worker, D1, R2, AI, DO, cron). This is the "how it works" doc.
- **`security.md`** — the security architecture: the auth gate (edge + in-Worker), identity, the encryption model (what's encrypted vs plaintext and why, key hierarchy, where keys live), secret management, and an honest **threat model + boundary** (what it protects against, what it explicitly does not). Reuse any boundary statement already in the repo README/ADRs rather than re-deriving.
- **`runbook.md`** — operational: how to deploy, how to **provision the whole thing from scratch** in a clean account (ordered commands), the token/scope requirements, env vars, how to roll back a deploy, how to rotate secrets, and the smoke test that proves the gate works.

Use mermaid for all diagrams (renders on GitHub). Prefer `flowchart` for topology, `sequenceDiagram` for flows, `erDiagram` for the data model if the app owns its schema. Keep diagrams readable: 5-12 nodes, not everything at once.

### 5. Idempotency + drift

- Regenerate the generated content on each run. Preserve any block wrapped in `<!-- HAND-EDITED START -->` / `<!-- HAND-EDITED END -->` verbatim.
- If config and live state disagree, add a **⚠️ Drift** callout naming the difference (e.g. "wrangler declares a `KV` binding with no live namespace").
- Stamp each doc with the date and the deployed version hash so staleness is visible.

### 6. Commit

Commit under the repo's convention (emoji + conventional: `📝 docs:`). Respect any commit-timestamp rules in the repo/global CLAUDE.md. Do NOT commit secret values (step 0 rule).

## Wiring it as an automatic post-deploy step

This skill is meant to run automatically once an app is live. Recommended wiring:

- **`/ro:cf-ship`, `/ro:gh-ship`, `/ro:fly-deploy`**: after the post-deploy smoke check passes, if `docs/infrastructure/` is absent (first deploy) OR the deploy changed bindings, invoke `/ro:infra-docs`. First deploy → always generate.
- **`/ro:app-polish`**: include "infrastructure docs present + current" as a checklist item.
- The skill is safe to run repeatedly, so a periodic re-run (after notable deploys) keeps the docs honest.

## Relationship to other skills

- `/ro:cf-ship` / `/ro:gh-ship` / `/ro:fly-deploy` — the deploy skills that should call this at their tail on first deploy.
- `/ro:generate-spec` / `/ro:compare-codebase-to-spec` — spec-level docs (intended behaviour); this skill is the infrastructure-level companion (what's actually deployed).
- `/ro:doc-standards` — house style for docs; follow it for prose.
- `/ro:security-audit` — the security doc here describes the model; that skill scans for leaks.

## Provenance

- **2026-05-22** — created in response to: "create detailed documentation on all the stuff in the cloud, sequence diagrams, whatever an architect would want ... this should always be done whenever we set up an application, once live, as a post-first-deployment step, and re-run periodically after deploys." First run: documenting the ADHD Helper deploy (Workers + D1 + R2 + Secrets Store + Workers AI + DO + Zero Trust Access + cron) in the personal Cloudflare account.
