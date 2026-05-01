---
name: better-auth
description: Wire Better Auth into a TanStack Start app as the optionality alt-path auth provider when you must own the user table, need EU data residency, or have fully custom auth flows. Default auth is /ro:clerk; alt-at-scale is /ro:workos. Use this skill when user explicitly wants Better Auth, owns-the-table semantics, EU-mandated user storage, or custom auth flows the vendored options cannot satisfy.
category: auth
argument-hint: [install | add-provider <github|google> | add-roles | generate-schema] [--email]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(openssl *) Bash(git *) Read Write Edit
---

# Better Auth

Wire [Better Auth](https://www.better-auth.com) into a TanStack Start + Drizzle + D1 app. Code-generates schema, server config, route handler, client, and optional OAuth providers and role helpers.

> **When to use this vs `/ro:clerk` / `/ro:workos`.** Default auth is `/ro:clerk` (hosted UI components, free to 10K MAU, fastest first sign-in). Alt-at-scale is `/ro:workos` (1M MAU free, hosted Admin Portal, B2B SSO ready). Reach for Better Auth when one of these is true:
> 1. You need to own the `users` table for native joins, FKs, and DB-enforced row-level security against merchant-scoped data.
> 2. EU data-residency mandate that neither Clerk nor vendored AuthKit can satisfy on their standard plans.
> 3. Fully custom auth flows (unusual onboarding, custom session shape, exotic providers) that Clerk and AuthKit do not bend to.
> 4. Zero vendor lock-in is a hard preference. The Auth.js consolidation under the Better Auth team in 2026 makes this the safest principled-OSS pick available.
>
> If none apply, prefer `/ro:clerk`.

## Usage

```
/ro:better-auth install                       # initial wiring (schema + server + client + route)
/ro:better-auth install --email               # + email/password with Resend for verification
/ro:better-auth add-provider github           # add GitHub OAuth
/ro:better-auth add-provider google           # add Google OAuth
/ro:better-auth add-roles                     # add roles plugin + helpers
/ro:better-auth generate-schema               # regen Drizzle schema after config change
```

## Prerequisites

- A TanStack Start app (`/ro:new-tanstack-app` or `/ro:migrate-to-tanstack`)
- Drizzle + D1 already wired (`src/db/schema.ts`, `wrangler.toml` with `[[d1_databases]]`)
- `RESEND_API_KEY` in `~/.claude/.env` if using `--email`

## Install flow

### 1. Install dependencies

```bash
pnpm add better-auth
pnpm add -D @better-auth/cli
```

### 2. Generate BETTER_AUTH_SECRET (per-app)

```bash
openssl rand -base64 32
```

Write it to the app's local env (NOT `~/.claude/.env` — this is per-app):

```bash
# .dev.vars
BETTER_AUTH_SECRET=<generated>
BETTER_AUTH_URL=http://localhost:3000
```

Push to production as a wrangler secret:

```bash
wrangler secret put BETTER_AUTH_SECRET
wrangler secret put BETTER_AUTH_URL     # = https://your-app.com
```

### 3. Server config — `src/lib/auth.ts`

```ts
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { db } from "@/db";
import * as schema from "@/db/schema";

export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "sqlite", schema }),
  emailAndPassword: { enabled: true },
  secret: process.env.BETTER_AUTH_SECRET,
  baseURL: process.env.BETTER_AUTH_URL,
});
```

### 4. Route handler — `src/routes/api/auth/$.ts`

TanStack Start Server Route:

```ts
import { createServerFileRoute } from "@tanstack/react-start/server";
import { auth } from "@/lib/auth";

export const ServerRoute = createServerFileRoute("/api/auth/$").methods({
  GET: ({ request }) => auth.handler(request),
  POST: ({ request }) => auth.handler(request),
});
```

### 5. Client — `src/lib/auth-client.ts`

```ts
import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({
  baseURL: import.meta.env.VITE_BETTER_AUTH_URL ?? window.location.origin,
});

export const { signIn, signUp, signOut, useSession } = authClient;
```

### 6. Generate schema

```bash
pnpx @better-auth/cli generate --config src/lib/auth.ts --output src/db/auth-schema.ts
```

Re-export from `src/db/schema.ts`:

```ts
export * from "./auth-schema";
```

### 7. Migration

```bash
pnpm drizzle-kit generate
wrangler d1 migrations apply <db-name> --local
wrangler d1 migrations apply <db-name> --remote
```

## add-provider

### GitHub

1. Create OAuth app: https://github.com/settings/applications/new
   - Homepage: `http://localhost:3000` (dev) or your domain
   - Callback: `<baseURL>/api/auth/callback/github`
2. Store secrets (per-app, NOT global):
   ```bash
   # .dev.vars
   GITHUB_CLIENT_ID=...
   GITHUB_CLIENT_SECRET=...
   # production
   wrangler secret put GITHUB_CLIENT_ID
   wrangler secret put GITHUB_CLIENT_SECRET
   ```
3. Patch `src/lib/auth.ts`:
   ```ts
   socialProviders: {
     github: {
       clientId: process.env.GITHUB_CLIENT_ID!,
       clientSecret: process.env.GITHUB_CLIENT_SECRET!,
     },
   },
   ```

### Google

Same pattern. Console: https://console.cloud.google.com/apis/credentials. Callback: `<baseURL>/api/auth/callback/google`.

## add-roles

```bash
pnpm add better-auth   # plugin included
```

Patch `src/lib/auth.ts`:

```ts
import { admin } from "better-auth/plugins";

export const auth = betterAuth({
  // ...existing...
  plugins: [admin({ defaultRole: "user", adminRoles: ["admin"] })],
});
```

Re-generate schema (`/ro:better-auth generate-schema`) to add `role` column on `user`.

Session check helper in Server Functions:

```ts
// src/lib/auth-server.ts
import { createServerFn } from "@tanstack/react-start";
import { auth } from "@/lib/auth";

export const requireSession = createServerFn({ method: "GET" }).handler(async ({ request }) => {
  const session = await auth.api.getSession({ headers: request.headers });
  if (!session) throw new Response("Unauthorized", { status: 401 });
  return session;
});

export const requireAdmin = createServerFn({ method: "GET" }).handler(async ({ request }) => {
  const session = await auth.api.getSession({ headers: request.headers });
  if (session?.user.role !== "admin") throw new Response("Forbidden", { status: 403 });
  return session;
});
```

## Email verification + password reset (`--email` flag)

Requires `RESEND_API_KEY` (global, `~/.claude/.env`).

Patch `src/lib/auth.ts`:

```ts
import { Resend } from "resend";

const resend = new Resend(process.env.RESEND_API_KEY);

export const auth = betterAuth({
  // ...existing...
  emailAndPassword: {
    enabled: true,
    requireEmailVerification: true,
    sendResetPassword: async ({ user, url }) => {
      await resend.emails.send({
        from: "no-reply@yourdomain.com",
        to: user.email,
        subject: "Reset your password",
        html: `<a href="${url}">Reset password</a>`,
      });
    },
  },
  emailVerification: {
    sendVerificationEmail: async ({ user, url }) => {
      await resend.emails.send({
        from: "no-reply@yourdomain.com",
        to: user.email,
        subject: "Verify your email",
        html: `<a href="${url}">Verify email</a>`,
      });
    },
  },
});
```

## Env var summary (per-app, NOT global)

| Var | Where | How to generate |
|---|---|---|
| `BETTER_AUTH_SECRET` | `.dev.vars` + wrangler secret | `openssl rand -base64 32` |
| `BETTER_AUTH_URL` | `.dev.vars` + wrangler secret | dev: `http://localhost:3000`; prod: app URL |
| `GITHUB_CLIENT_ID/SECRET` | `.dev.vars` + wrangler secret | GitHub OAuth app |
| `GOOGLE_CLIENT_ID/SECRET` | `.dev.vars` + wrangler secret | Google Cloud Console OAuth credentials |

`RESEND_API_KEY` is the exception — it's global (`~/.claude/.env`), shared across all apps.

## Safety

- Never put `BETTER_AUTH_SECRET` in `~/.claude/.env` — it MUST be per-app so compromise of one app doesn't forge sessions for all apps.
- Never commit `.dev.vars`. Verify `.gitignore` includes it before `/ro:better-auth install` exits.
- When adding an OAuth provider, verify the callback URL matches the registered app exactly — mismatches produce opaque 400s.
- Do not delete existing `user`/`session`/`account`/`verification` tables without an explicit migration plan — this skill only adds, never drops.

## See also

- `/ro:clerk` is the **default for small SaaS** (hosted UI components, free to 10K MAU, fastest first sign-in). Start there unless one of the four Better-Auth triggers above applies.
- `/ro:workos` for the alt-at-scale case (vendored auth, hosted Admin Portal, B2B SSO ready, 1M MAU free, when you do not need to own the user table)
- `/ro:new-tanstack-app --auth=better-auth` to scaffold a new app with Better Auth pre-wired (default is `--auth=clerk`)
- `/ro:cf-ship` to ship after wiring
- Better Auth docs: https://www.better-auth.com, use context7 for current syntax
- Comparison pages: `llm-wiki-research/wiki/comparisons/auth-clerk-vs-better-auth.md`, `auth-three-way-deep-dive.md`
