---
name: workos
description: ARCHIVED 2026-05-01. WorkOS AuthKit wiring for TanStack Start on Cloudflare Workers. Pulled from active skills because the user's product portfolio is small SaaS and won't hit 10K MAU. Restore when (a) MAU genuinely approaches 100K, (b) a non-engineer partner needs the WorkOS hosted Admin Portal sidecar, or (c) per-connection SAML SSO is a near-term selling point. To restore, move this directory back to `skills/workos/` and `git push` (the pre-push hook will bump the plugin version). Default auth is now /ro:clerk; alt for own-the-table is /ro:better-auth.
category: auth-archived
argument-hint: [install | add-organizations | add-sso | add-webhook | open-portal] [--social github,google]
archived: true
archived-date: 2026-05-01
archived-reason: "Demoted from default in favour of /ro:clerk. User's product portfolio is small SaaS, speed-to-market priority, won't hit 10K MAU. WorkOS's 1M-MAU-free advantage and Admin Portal sidecar are valuable but irrelevant at this scale."
restore-when: "(a) MAU growth past 10K becomes a real near-term plan, OR (b) a non-engineer partner explicitly asks for hosted user-management visibility, OR (c) enterprise SAML SSO is a near-term sale."
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(openssl *) Bash(git *) Bash(open *) Read Write Edit
---

> **🗄️ ARCHIVED 2026-05-01**
>
> This skill is intentionally outside `skills/` so the plugin loader skips it. The body below is unchanged from the active version, ready to use as-is when restored.
>
> **Why archived:** The auth canon flipped from WorkOS-default to Clerk-default for small SaaS speed-to-market. WorkOS's headline advantages (1M MAU free tier, hosted Admin Portal sidecar) are real but don't apply to products that won't pass 10K MAU.
>
> **To restore:** `git mv archive/skills/workos skills/workos && git push` from `~/Dev/ronan-skills/`. The pre-push hook will bump the plugin version automatically.
>
> **Restore triggers** (any one is sufficient):
> 1. MAU expected to cross 10K within 12 months (Clerk's per-MAU cost starts ramping there)
> 2. A non-engineer partner explicitly needs hosted user-management visibility without full Clerk dashboard access
> 3. A customer or partnership pipeline is asking for enterprise SAML SSO
>
> **See also:** `/ro:clerk` (current default), `/ro:better-auth` (alt for owns-the-table / EU mandate). Comparisons: `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`.

# WorkOS

Wire [WorkOS AuthKit](https://workos.com/docs/user-management) into a TanStack Start + Drizzle + D1 app on Cloudflare Workers. Hosted sign-in UI, sealed-session cookie, organisations + Admin Portal for non-engineer partners, SSO when an enterprise merchant asks.

This is the **alt-at-scale** auth pick for the user's stack as of 2026-05-01. The default for small SaaS is `/ro:clerk` (broader hosted-component catalogue, faster first sign-in, free to 10K MAU). Reach for WorkOS when one of these triggers fires:

1. MAU is expected to cross 100K within 12 months (Clerk's per-MAU cost ramps; WorkOS is free to 1M MAU).
2. A non-engineer partner needs the hosted Admin Portal for user-management visibility (Clerk's dashboard works but WorkOS's Admin Portal is built around handing access to a partner without giving them the full dashboard).
3. Enterprise SSO via per-connection SAML is on the near-term roadmap (WorkOS owns this category; Clerk supports it but at higher per-connection cost).

For the inverse case (own the user table, EU residency mandate, fully custom flows), use `/ro:better-auth` instead. Comparisons: `llm-wiki-research/wiki/comparisons/auth-clerk-vs-better-auth.md` and `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`.

## Usage

```
/ro:workos install                              # initial wiring (env + sign-in + callback + middleware)
/ro:workos install --social github,google       # + GitHub + Google providers
/ro:workos add-organizations                    # multi-tenant orgs + switcher
/ro:workos add-webhook                          # /api/webhooks/workos with signature verification
/ro:workos add-sso                              # SAML SSO, $125/mo per connection at time of writing
/ro:workos open-portal                          # open the WorkOS dashboard for this app
```

## Prerequisites

- A TanStack Start app (`/ro:new-tanstack-app` or `/ro:migrate-to-tanstack`)
- Drizzle + D1 already wired (`src/db/schema.ts`, `wrangler.toml` with `[[d1_databases]]`)
- A WorkOS account (free, sign up at workos.com), one Application created in the dashboard

## Install flow

### 1. Install dependencies

```bash
pnpm add @workos-inc/authkit-session @workos-inc/node
```

The `authkit-session` package is the framework-agnostic toolkit (works in Workers). `@workos-inc/node` is the server SDK for management API calls (webhooks, user lookup, org membership).

### 2. Generate `WORKOS_COOKIE_PASSWORD` (per-app)

```bash
openssl rand -base64 32
```

Must be at least 32 characters. WorkOS uses it to seal the session cookie (iron-webcrypto + AES-256).

### 3. Per-app env vars

```bash
# .dev.vars
WORKOS_CLIENT_ID=client_01ABC
WORKOS_API_KEY=sk_test_...
WORKOS_REDIRECT_URI=http://localhost:3000/api/auth/callback
WORKOS_COOKIE_PASSWORD=<openssl output>
```

Production secrets:

```bash
wrangler secret put WORKOS_CLIENT_ID
wrangler secret put WORKOS_API_KEY
wrangler secret put WORKOS_REDIRECT_URI       # = https://your-app.com/api/auth/callback
wrangler secret put WORKOS_COOKIE_PASSWORD
```

`WORKOS_CLIENT_ID` and the public sign-in domain come from your Application page in the WorkOS dashboard. `WORKOS_API_KEY` is per-environment (separate test + live keys).

### 4. Auth service module, `src/lib/auth.ts`

The Workers runtime has no `process.env`, so configure programmatically from the request `env` binding.

```ts
import { configure, AuthService } from '@workos-inc/authkit-session';

let configured = false;

export function getAuth(env: Env) {
  if (!configured) {
    configure({
      clientId: env.WORKOS_CLIENT_ID,
      apiKey: env.WORKOS_API_KEY,
      redirectUri: env.WORKOS_REDIRECT_URI,
      cookiePassword: env.WORKOS_COOKIE_PASSWORD,
      cookieName: 'wos-session',
      cookieMaxAge: 60 * 60 * 24 * 30,
      cookieSameSite: 'lax',
    });
    configured = true;
  }
  return new AuthService();
}
```

Add the env shape to your `Env` type, usually in `worker-configuration.d.ts` (regenerated by `wrangler types`).

### 5. Sign-in route, `src/routes/api/auth/sign-in.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getAuth } from '@/lib/auth';

export const ServerRoute = createServerFileRoute('/api/auth/sign-in').methods({
  GET: async ({ request, context }) => {
    const auth = getAuth(context.cloudflare.env);
    const { url, headers } = await auth.createSignIn(undefined, {
      returnPathname: new URL(request.url).searchParams.get('returnTo') ?? '/dashboard',
    });
    const res = new Response(null, { status: 302, headers: { Location: url } });
    for (const [k, v] of Object.entries(headers)) {
      const values = Array.isArray(v) ? v : [v];
      for (const val of values) res.headers.append(k, val);
    }
    return res;
  },
});
```

### 6. Callback route, `src/routes/api/auth/callback.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getAuth } from '@/lib/auth';

export const ServerRoute = createServerFileRoute('/api/auth/callback').methods({
  GET: async ({ request, context }) => {
    const auth = getAuth(context.cloudflare.env);
    const url = new URL(request.url);
    const code = url.searchParams.get('code');
    const state = url.searchParams.get('state') ?? undefined;

    if (!code) return new Response('Missing code', { status: 400 });

    try {
      const result = await auth.handleCallback(request, new Response(), { code, state });
      const redirect = result.returnPathname ?? '/dashboard';
      const res = new Response(null, { status: 302, headers: { Location: redirect } });
      const setCookie = result.headers?.['Set-Cookie'] ?? result.headers?.['set-cookie'];
      if (setCookie) {
        for (const v of Array.isArray(setCookie) ? setCookie : [setCookie]) {
          res.headers.append('Set-Cookie', v);
        }
      }
      return res;
    } catch {
      return Response.redirect('/sign-in?error=auth_failed', 302);
    }
  },
});
```

### 7. Sign-out route, `src/routes/api/auth/sign-out.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getAuth } from '@/lib/auth';

export const ServerRoute = createServerFileRoute('/api/auth/sign-out').methods({
  POST: async ({ context }) => {
    const auth = getAuth(context.cloudflare.env);
    const { url, headers } = await auth.createSignOut();
    const res = new Response(null, { status: 302, headers: { Location: url } });
    for (const [k, v] of Object.entries(headers)) {
      const values = Array.isArray(v) ? v : [v];
      for (const val of values) res.headers.append(k, val);
    }
    return res;
  },
});
```

### 8. Server helper, `src/lib/auth-server.ts`

```ts
import { createServerFn } from '@tanstack/react-start';
import { getAuth } from '@/lib/auth';
import { getEvent } from '@tanstack/react-start/server';

export const requireSession = createServerFn({ method: 'GET' }).handler(async () => {
  const event = getEvent();
  const auth = getAuth(event.context.cloudflare.env);
  const { auth: session } = await auth.withAuth(event.request);
  if (!session.user) throw new Response('Unauthorized', { status: 401 });
  return {
    userId: session.user.id,
    email: session.user.email,
    organizationId: session.organizationId,
    roles: session.roles ?? [],
  };
});
```

`withAuth` returns `auth.user`, `auth.sessionId`, `auth.organizationId`, `auth.roles`, `auth.permissions`, `auth.entitlements`. If tokens were refreshed, also persist `refreshedSessionData` via `auth.saveSession(...)` and append the returned cookies to your response, otherwise you will hit an infinite refresh loop on the next request.

### 9. Client sign-in button

No client SDK needed. Just link to the server route.

```tsx
// src/components/sign-in-button.tsx
export function SignInButton() {
  return <a href="/api/auth/sign-in?returnTo=/dashboard">Sign in</a>;
}
```

User data flows from `requireSession` server function into the route loader, then to the page.

## --social github,google

WorkOS handles social providers in the dashboard, no app code change. Open the Application page, enable GitHub or Google under "Authentication providers", paste the OAuth client ID + secret you got from each provider's developer console.

Callback URL to register on the provider side: `https://api.workos.com/sso/oauth/google/<client-id>/launch`. The dashboard shows the exact value.

## add-organizations

WorkOS organisations are free (included to 1M MAU). Each `Organization` has Members and Roles. Switch the active org by passing `organizationId` to `createSignIn` or by calling the org-switch helper:

```ts
// src/routes/api/auth/switch-org.ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getAuth } from '@/lib/auth';

export const ServerRoute = createServerFileRoute('/api/auth/switch-org').methods({
  POST: async ({ request, context }) => {
    const form = await request.formData();
    const organizationId = form.get('organizationId') as string;
    const auth = getAuth(context.cloudflare.env);
    const { url, headers } = await auth.createSignIn(undefined, {
      organizationId,
      returnPathname: '/dashboard',
    });
    const res = new Response(null, { status: 302, headers: { Location: url } });
    for (const [k, v] of Object.entries(headers)) {
      const values = Array.isArray(v) ? v : [v];
      for (const val of values) res.headers.append(k, val);
    }
    return res;
  },
});
```

The session cookie is replaced with one scoped to the new org. Roles + permissions in `auth.roles` are now org-scoped.

## add-webhook

WorkOS pushes events on user.deleted, user.updated, organization-membership changes. You need a shadow `users` row in your D1 to join app data against.

### Drizzle schema

```ts
// src/db/schema.ts
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

export const users = sqliteTable('users', {
  id: text('id').primaryKey(),                    // workos user_01...
  email: text('email').notNull(),
  firstName: text('first_name'),
  lastName: text('last_name'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull().$defaultFn(() => new Date()),
  updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull().$defaultFn(() => new Date()),
  deletedAt: integer('deleted_at', { mode: 'timestamp' }),
});
```

Foreign keys from your domain tables point at `users.id` (the WorkOS user ID, not an internal one).

### Webhook route, `src/routes/api/webhooks/workos.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import WorkOS from '@workos-inc/node';
import { db } from '@/db';
import { users } from '@/db/schema';
import { eq } from 'drizzle-orm';

export const ServerRoute = createServerFileRoute('/api/webhooks/workos').methods({
  POST: async ({ request, context }) => {
    const env = context.cloudflare.env;
    const workos = new WorkOS(env.WORKOS_API_KEY);
    const sig = request.headers.get('workos-signature');
    if (!sig) return new Response('Missing signature', { status: 400 });

    const body = await request.text();
    let event;
    try {
      event = await workos.webhooks.constructEvent({
        payload: JSON.parse(body),
        sigHeader: sig,
        secret: env.WORKOS_WEBHOOK_SECRET,
      });
    } catch {
      return new Response('Bad signature', { status: 400 });
    }

    switch (event.event) {
      case 'user.created':
      case 'user.updated':
        await db.insert(users).values({
          id: event.data.id,
          email: event.data.email,
          firstName: event.data.firstName,
          lastName: event.data.lastName,
        }).onConflictDoUpdate({
          target: users.id,
          set: {
            email: event.data.email,
            firstName: event.data.firstName,
            lastName: event.data.lastName,
            updatedAt: new Date(),
          },
        });
        break;
      case 'user.deleted':
        await db.update(users).set({ deletedAt: new Date() }).where(eq(users.id, event.data.id));
        break;
    }
    return new Response('ok');
  },
});
```

Add `WORKOS_WEBHOOK_SECRET` (separate from `WORKOS_API_KEY`) as a wrangler secret. Create the webhook endpoint in WorkOS dashboard, copy the signing secret, point it at `https://your-app.com/api/webhooks/workos`.

The shadow row is the tradeoff vs Better Auth. You do not own user attributes (email change happens in WorkOS, syncs to you). Custom fields go in a separate table keyed by `users.id`.

## add-sso

Enterprise merchants asking for SAML / OIDC SSO is the moment WorkOS earns its keep. Each connection is $125/mo at the time of writing (verify on workos.com/pricing). Wiring is one config flip:

1. In the WorkOS dashboard, create a new SSO Connection scoped to the merchant's Organization.
2. The merchant uploads their IdP metadata or uses Connect-style flow.
3. Already-existing sign-in flow auto-routes that org's users to SSO. No app code change.

Members of an SSO-enabled org get bounced through the IdP automatically.

## open-portal

WorkOS Admin Portal lets a non-engineer partner manage users, orgs, and SSO connections without touching code. Generate a one-time link from the server SDK:

```ts
import WorkOS from '@workos-inc/node';

const workos = new WorkOS(env.WORKOS_API_KEY);
const { link } = await workos.portal.generateLink({
  organization: 'org_01ABC',
  intent: 'sso',  // or 'dsync', 'audit_logs', 'log_streams'
});
// share `link` with the partner, expires in 5 minutes
```

For full WorkOS dashboard access (your own admin work), invite the partner as a Team Member in the Organization Settings page of the WorkOS dashboard.

## Env var summary (per-app, NOT global)

| Var | Where | Source |
|---|---|---|
| `WORKOS_CLIENT_ID` | `.dev.vars` + wrangler secret | WorkOS dashboard, Application page |
| `WORKOS_API_KEY` | `.dev.vars` + wrangler secret | WorkOS dashboard, API Keys (separate test + live) |
| `WORKOS_REDIRECT_URI` | `.dev.vars` + wrangler secret | dev: `http://localhost:3000/api/auth/callback`, prod: `https://app.com/api/auth/callback` |
| `WORKOS_COOKIE_PASSWORD` | `.dev.vars` + wrangler secret | `openssl rand -base64 32` |
| `WORKOS_WEBHOOK_SECRET` | wrangler secret (only after add-webhook) | WorkOS dashboard, webhook endpoint detail |

## EU residency caveat

AuthKit user PII is stored in the US by default with Data Privacy Framework transfers. Mandated EU residency is Enterprise plan, custom contract. If a Dutch merchant in your customer base names this as a hard requirement, your two options are:

1. Move that customer onto an Enterprise contract.
2. Migrate the whole app off WorkOS to `/ro:better-auth` (your DB, your region).

For the user's current Simplicity x Taskforce partnership the team has decided residency is a tiebreaker, not a hard constraint. Document the trigger conditions in the project's `auth-strategy.md` so the flip is a known move.

## Migration off later

If you flip away from WorkOS to a self-hosted setup, the path is:

1. Use the `users.list` API to export every user (paginated). Save email + WorkOS ID + first/last name + email-verified flag.
2. Bulk-create accounts in the new system, keyed by email. Map `workos_user_id` to the new internal ID in your domain tables.
3. Send a "we have moved, set a new password" email to all active users (you do not have access to original passwords, AuthKit only stores hashes on its side).
4. Run both systems in parallel for a week so users who miss the email can still get in via WorkOS, then cut over.

Plan one engineer-week and a week of soft migration window. Not free, not catastrophic.

## Safety

- Never put `WORKOS_API_KEY` or `WORKOS_COOKIE_PASSWORD` in `~/.claude/.env`. Per-app secrets only. A leaked cookie password lets anyone forge sessions for that one app.
- `WORKOS_REDIRECT_URI` must match exactly what is registered in the WorkOS Application's Redirect URIs list. Mismatches return opaque 400s.
- Do not skip the `Set-Cookie` append loop in the callback handler. WorkOS sends two `Set-Cookie` values (session cookie plus PKCE verifier delete) and they must each become a separate header.
- Webhook handlers must verify the signature before trusting the payload. The example above does this via `workos.webhooks.constructEvent`. Skipping the check lets anyone spoof user.deleted.

## See also

- `/ro:clerk` is the **now-default for small-SaaS speed-to-market** (broader hosted components, free to 10K MAU). Start there unless one of the three WorkOS triggers above applies.
- `/ro:better-auth` for the inverse case (own the user table, EU mandate, fully custom flows)
- `/ro:nango` when wiring third-party integrations (Nango sessions are scoped to your authenticated end-user)
- `/ro:stripe` when wiring payments (Stripe customers are linked to WorkOS user IDs)
- `/ro:new-tanstack-app --auth=workos` to scaffold a new app with WorkOS pre-wired (default is `--auth=clerk`)
- `/ro:cf-ship` to ship after wiring
- WorkOS docs: https://workos.com/docs/user-management, use context7 (`/workos/authkit-session`) for current syntax
- Comparison pages: `llm-wiki-research/wiki/comparisons/auth-clerk-vs-better-auth.md`, `auth-three-way-deep-dive.md`
