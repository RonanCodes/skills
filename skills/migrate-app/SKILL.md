---
name: migrate-app
description: Generic "migrate an existing project" dispatcher. Asks the source stack and the target shape via AskUserQuestion, then hands off to the framework-specific migration skill (`/ro:migrate-to-tanstack`, `/ro:migrate-to-astro`). Use when the user wants to migrate, port, move, or convert an existing web app but isn't sure which target stack fits. Sister to `/ro:new-app` — same dispatcher pattern, the migration leaves of `[[stack-decision-map]]`. Calls neither skill until the user confirms the chosen target.
category: project-setup
argument-hint: [--source <framework>] [--target <framework>] [--explain]
allowed-tools: Bash(cat *) Bash(git *) Bash(grep *) Bash(jq *) Read AskUserQuestion
---

# Migrate App (migration dispatcher)

Walks the migration question — what's the source, what's the target — and dispatches to the right `/ro:migrate-to-<framework>` skill. Doesn't port anything itself.

If you already know the target, call the leaf skill directly:
- `/ro:migrate-to-tanstack` — porting to server-leaning TanStack Start + D1 + Workers
- `/ro:migrate-to-astro` — porting to static-leaning Astro 5 on Workers (with the live-DNS cutover sequence)

This skill is the "I'm not sure which target fits" entry point.

## Usage

```
/ro:migrate-app
/ro:migrate-app --source vercel-astro --target astro
/ro:migrate-app --explain
```

## Process

### 1. Audit the source (always run first)

If running in a repo, do a quick audit before asking anything — the answers often jump out:

```bash
# Current adapter / framework
grep -E "@astrojs/(vercel|netlify|cloudflare|node)|next|remix|nuxt|sveltekit" package.json
# Current output mode (Astro)
grep -E "output:\s*['\"](static|server|hybrid)" astro.config.* 2>/dev/null
# Hosting hints
ls vercel.json netlify.toml fly.toml Dockerfile 2>/dev/null
```

Echo the findings before the first question so the user sees what was detected.

### 2. Source stack (`AskUserQuestion`):

- Astro on Vercel
- Astro on a VPS (Hetzner, DigitalOcean, etc.)
- Astro on Cloudflare Pages
- Next.js (Vercel, Netlify, or self-hosted)
- Vite + Hono / Express / fastify
- Plain HTML / WordPress / Webflow export
- Other (custom — ask follow-up)

### 3. Target shape (`AskUserQuestion`):

- **Static-leaning** marketing / portfolio / blog (mostly content, only `/api/*` is dynamic) → `/ro:migrate-to-astro`
- **Server-leaning** SaaS / app (auth, dynamic routes, DB, runtime API surface) → `/ro:migrate-to-tanstack`

If the source is already Astro and the target is static-leaning, the migration is mostly a hosting swap — `/ro:migrate-to-astro` handles that path with explicit checks for the twelve `[[astro-cf-workers-migration-gotchas]]`.

If the source is Astro but the target is server-leaning (e.g. you're outgrowing the Astro adapter and need a real SaaS), prompt: "this is a rewrite, not a port — confirm?" before dispatching to `/ro:migrate-to-tanstack`.

### 4. Cutover risk check

Before dispatching, ask:

- **Live domain?** If yes, the chosen migration skill walks the cutover-with-existing-DNS sequence. Confirm the user has a rollback plan (DNS records of the source side captured, source server kept up for a week post-cutover).
- **Data migration needed?** Only relevant for server-leaning targets with a database. If yes, the chosen skill needs `--keep-data`.

### 5. Confirm + hand off

Print the exact dispatch invocation, ask for confirmation, then run it.

```
Based on your answers:
  - source: Astro on a Hetzner VPS
  - target: static-leaning (mostly marketing pages + /api/config)
  - live domain: yes (cutover with rollback plan)

About to run: /ro:migrate-to-astro --strategy branch

Continue? (yes/edit-decisions/no)
```

## Dispatch matrix (current as of 2026-05-05)

| Source | Target shape | Dispatches to | Notes |
|---|---|---|---|
| Astro (any host) | static-leaning | `/ro:migrate-to-astro` | Most common — Vercel/VPS Astro → Workers |
| Next.js | static-leaning | `/ro:migrate-to-astro` | Treated as a rewrite (drop Next, port content + components to Astro) |
| Plain HTML / Webflow / WP | static-leaning | `/ro:migrate-to-astro` | Use `--strategy fresh` |
| Anything | server-leaning | `/ro:migrate-to-tanstack` | Always a rewrite, never a host swap |
| Astro | server-leaning | `/ro:migrate-to-tanstack` | Rewrite — confirm with user before dispatch |

## See also

- `[[astro-cf-workers-migration-gotchas]]` — the spec `/ro:migrate-to-astro` implements
- `/ro:migrate-to-astro`, `/ro:migrate-to-tanstack` — the leaves this dispatcher routes to
- `/ro:new-app` — the sibling for fresh projects (no source to port)
- `[[stack-decision-map]]` — the canonical tree both dispatchers walk
