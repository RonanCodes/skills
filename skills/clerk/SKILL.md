---
name: clerk
description: Wire Clerk into a TanStack Start app on Cloudflare Workers, install, env config, ClerkProvider + drop-in UI components (SignIn, SignUp, UserButton, OrganizationSwitcher), server-side authenticateRequest helper, Drizzle shadow user table, webhook signature verification, organisations + multi-tenancy. Default auth pick for small SaaS where speed-to-market and out-of-the-box UI matter. Use when user wants to add Clerk, add auth, wire login, sign-in component, user button, organisation switcher, small SaaS auth, fastest auth, Clerk middleware, or hosted auth UI.
category: auth
argument-hint: [install | add-organizations | add-webhook | open-dashboard] [--social github,google]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(open *) Read Write Edit
---

# Clerk

Wire [Clerk](https://clerk.com) into a TanStack Start + Drizzle + D1 app on Cloudflare Workers. Hosted sign-in UI with drop-in React components, server-side session verification via `@clerk/backend`, organisations as first-class for B2B.

This is the canonical auth pick for the user's stack as of 2026-04-30. Optimised for small SaaS where speed-to-first-working-sign-in matters more than scale features. For B2B-at-scale (100K+ MAU expected, partner needs hosted Admin Portal, near-term SAML SSO), use `/ro:workos`. For own-the-table semantics (RLS / FKs / EU residency mandate / fully custom flows), use `/ro:better-auth`. Comparisons: `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`.

## Usage

```
/ro:clerk install                              # initial wiring (env + provider + sign-in routes + middleware)
/ro:clerk install --social github,google       # + GitHub + Google providers
/ro:clerk add-organizations                    # multi-tenant orgs + OrganizationSwitcher
/ro:clerk add-webhook                          # /api/webhooks/clerk with svix signature verification
/ro:clerk open-dashboard                       # open the Clerk dashboard for this app
```

## Prerequisites

- A TanStack Start app (`/ro:new-tanstack-app` or `/ro:migrate-to-tanstack`)
- Drizzle + D1 already wired (`src/db/schema.ts`, `wrangler.toml` with `[[d1_databases]]`)
- A Clerk account (free, sign up at clerk.com), one Application created in the dashboard

## Install flow

### 1. Install dependencies

```bash
pnpm add @clerk/clerk-react @clerk/backend
pnpm add svix     # for webhook signature verification (only if using add-webhook)
```

`@clerk/clerk-react` ships the drop-in components. `@clerk/backend` does session verification, runs in Workers (no Node-only APIs).

### 2. Per-app env vars

```bash
# .dev.vars
CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
CLERK_WEBHOOK_SECRET=whsec_...      # only after add-webhook
```

The publishable key is safe to expose in the client bundle. The secret key and webhook secret stay server-side.

Production secrets:

```bash
wrangler secret put CLERK_PUBLISHABLE_KEY
wrangler secret put CLERK_SECRET_KEY
wrangler secret put CLERK_WEBHOOK_SECRET     # only after add-webhook
```

Both keys come from the Clerk dashboard, API Keys page. Production keys (`pk_live_`, `sk_live_`) are separate from test keys.

### 3. Wrap the app with ClerkProvider, `src/router.tsx` or `src/main.tsx`

```tsx
import { ClerkProvider } from '@clerk/clerk-react';

const publishableKey = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY;
if (!publishableKey) throw new Error('Missing VITE_CLERK_PUBLISHABLE_KEY');

// In your root route or main render:
<ClerkProvider publishableKey={publishableKey}>
  <App />
</ClerkProvider>
```

The `VITE_CLERK_PUBLISHABLE_KEY` lands in the bundle at build time. Map it from `CLERK_PUBLISHABLE_KEY` in `vite.config.ts` or expose via `/api/config` if you want runtime injection (see `/ro:new-tanstack-app` step 9 for the runtime-config pattern).

### 4. Drop-in sign-in route, `src/routes/sign-in.tsx`

```tsx
import { createFileRoute } from '@tanstack/react-router';
import { SignIn } from '@clerk/clerk-react';

export const Route = createFileRoute('/sign-in')({
  component: () => (
    <div className="flex min-h-screen items-center justify-center">
      <SignIn routing="path" path="/sign-in" signUpUrl="/sign-up" forceRedirectUrl="/dashboard" />
    </div>
  ),
});
```

Mirror with `src/routes/sign-up.tsx` using `<SignUp />`. That is the entire sign-in UI. No callback handler to write, Clerk's hosted flow handles OAuth round-trips and email verification.

### 5. UserButton in the app shell

```tsx
import { UserButton } from '@clerk/clerk-react';

export function AppHeader() {
  return (
    <header className="flex items-center justify-between p-4">
      <Logo />
      <UserButton afterSignOutUrl="/" />
    </header>
  );
}
```

`<UserButton />` renders the avatar with a menu including profile, account settings, sign-out, and (if orgs enabled) org switcher. This is the headline DX argument for Clerk vs the alternatives.

### 6. Server-side session verification, `src/lib/auth-server.ts`

```ts
import { createServerFn } from '@tanstack/react-start';
import { getEvent } from '@tanstack/react-start/server';
import { createClerkClient } from '@clerk/backend';

export function getClerk(env: Env) {
  return createClerkClient({
    secretKey: env.CLERK_SECRET_KEY,
    publishableKey: env.CLERK_PUBLISHABLE_KEY,
  });
}

export const requireSession = createServerFn({ method: 'GET' }).handler(async () => {
  const event = getEvent();
  const clerk = getClerk(event.context.cloudflare.env);
  const { isAuthenticated, toAuth } = await clerk.authenticateRequest(event.request);
  if (!isAuthenticated) throw new Response('Unauthorized', { status: 401 });
  const auth = toAuth();
  return {
    userId: auth.userId,
    sessionId: auth.sessionId,
    organizationId: auth.orgId,
    role: auth.orgRole,
  };
});
```

`authenticateRequest` reads the session cookie or `Authorization: Bearer` header, verifies the JWT against Clerk's public keys (cached in the Worker), and returns the auth state. No round-trip to Clerk's servers per request.

### 7. Protect a route loader

```ts
// src/routes/dashboard.tsx
import { createFileRoute, redirect } from '@tanstack/react-router';
import { requireSession } from '@/lib/auth-server';

export const Route = createFileRoute('/dashboard')({
  beforeLoad: async () => {
    try {
      return { auth: await requireSession() };
    } catch {
      throw redirect({ to: '/sign-in' });
    }
  },
  component: DashboardPage,
});
```

The session shape from `requireSession` flows to the page via `Route.useRouteContext()`.

## --social github,google

Clerk handles social providers in the dashboard, no app code change. Open the Application page, navigate to "User & Authentication" → "Social Connections", toggle GitHub or Google, paste the OAuth client ID + secret you got from each provider's developer console.

Callback URLs to register on the provider side are shown in the Clerk dashboard (per-provider, with copy buttons).

## add-organizations

Clerk Organizations are first-class. Each `Organization` has Members, Roles, Invitations. Free up to 10K MAU.

Add the switcher anywhere in the shell:

```tsx
import { OrganizationSwitcher } from '@clerk/clerk-react';

export function AppHeader() {
  return (
    <header className="flex items-center gap-4 p-4">
      <Logo />
      <OrganizationSwitcher
        afterCreateOrganizationUrl="/dashboard"
        afterSelectOrganizationUrl="/dashboard"
      />
      <UserButton afterSignOutUrl="/" />
    </header>
  );
}
```

The active org propagates to `auth.orgId` on the server (visible in `requireSession` above). Org-scoped data fetching:

```ts
const { organizationId } = await requireSession();
const rows = await db.select().from(merchants).where(eq(merchants.orgId, organizationId));
```

Client-side hooks: `useOrganization()` returns the current org and membership, `useOrganizationList()` for switching, `useUser()` for the user object.

For per-org RBAC, use Clerk's built-in roles (`org:admin`, `org:member`, custom). `auth.orgRole` returns the active member's role, and Clerk's `<Protect>` component gates UI:

```tsx
import { Protect } from '@clerk/clerk-react';

<Protect role="org:admin">
  <DangerZone />
</Protect>
```

## add-webhook

Clerk pushes events on user.created, user.updated, user.deleted, organization.created, etc. Sync to a shadow `users` row in your D1 so domain tables can FK to it.

### Drizzle schema

```ts
// src/db/schema.ts
import { sqliteTable, text, integer } from 'drizzle-orm/sqlite-core';

export const users = sqliteTable('users', {
  id: text('id').primaryKey(),                    // clerk user_2abc...
  email: text('email').notNull(),
  firstName: text('first_name'),
  lastName: text('last_name'),
  imageUrl: text('image_url'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull().$defaultFn(() => new Date()),
  updatedAt: integer('updated_at', { mode: 'timestamp' }).notNull().$defaultFn(() => new Date()),
  deletedAt: integer('deleted_at', { mode: 'timestamp' }),
});

export const organizations = sqliteTable('organizations', {
  id: text('id').primaryKey(),                    // clerk org_2xyz...
  name: text('name').notNull(),
  slug: text('slug'),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull().$defaultFn(() => new Date()),
});
```

Foreign keys from your domain tables point at `users.id` (the Clerk user ID, not an internal one).

### Webhook route, `src/routes/api/webhooks/clerk.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { Webhook } from 'svix';
import { db } from '@/db';
import { users, organizations } from '@/db/schema';
import { eq } from 'drizzle-orm';

export const ServerRoute = createServerFileRoute('/api/webhooks/clerk').methods({
  POST: async ({ request, context }) => {
    const env = context.cloudflare.env;
    const svixId = request.headers.get('svix-id');
    const svixTimestamp = request.headers.get('svix-timestamp');
    const svixSignature = request.headers.get('svix-signature');
    if (!svixId || !svixTimestamp || !svixSignature) {
      return new Response('Missing svix headers', { status: 400 });
    }

    const body = await request.text();
    const wh = new Webhook(env.CLERK_WEBHOOK_SECRET);
    let event;
    try {
      event = wh.verify(body, {
        'svix-id': svixId,
        'svix-timestamp': svixTimestamp,
        'svix-signature': svixSignature,
      }) as { type: string; data: any };
    } catch {
      return new Response('Bad signature', { status: 400 });
    }

    switch (event.type) {
      case 'user.created':
      case 'user.updated':
        await db.insert(users).values({
          id: event.data.id,
          email: event.data.email_addresses[0]?.email_address ?? '',
          firstName: event.data.first_name,
          lastName: event.data.last_name,
          imageUrl: event.data.image_url,
        }).onConflictDoUpdate({
          target: users.id,
          set: {
            email: event.data.email_addresses[0]?.email_address ?? '',
            firstName: event.data.first_name,
            lastName: event.data.last_name,
            imageUrl: event.data.image_url,
            updatedAt: new Date(),
          },
        });
        break;
      case 'user.deleted':
        await db.update(users).set({ deletedAt: new Date() }).where(eq(users.id, event.data.id));
        break;
      case 'organization.created':
      case 'organization.updated':
        await db.insert(organizations).values({
          id: event.data.id,
          name: event.data.name,
          slug: event.data.slug,
        }).onConflictDoUpdate({
          target: organizations.id,
          set: { name: event.data.name, slug: event.data.slug },
        });
        break;
    }
    return new Response('ok');
  },
});
```

In the Clerk dashboard, navigate to Webhooks, create an endpoint pointing at `https://your-app.com/api/webhooks/clerk`, copy the signing secret, push it as `CLERK_WEBHOOK_SECRET` (per-app, NOT global).

The shadow row is the tradeoff vs Better Auth. You do not own user attributes (email change happens in Clerk, syncs to you). Custom fields go in a separate table keyed by `users.id`.

## open-dashboard

Open the Clerk dashboard for this app:

```bash
open https://dashboard.clerk.com
```

Non-tech partners can be invited as Team Members under Organization Settings, with limited or admin scopes. They get a hosted UI to manage users, see signups, reset passwords, ban accounts, configure providers.

## Env var summary (per-app, NOT global)

| Var | Where | Source |
|---|---|---|
| `CLERK_PUBLISHABLE_KEY` | `.dev.vars` + wrangler secret | Clerk dashboard, API Keys (separate test + live) |
| `CLERK_SECRET_KEY` | `.dev.vars` + wrangler secret | Clerk dashboard, API Keys |
| `CLERK_WEBHOOK_SECRET` | wrangler secret (only after add-webhook) | Clerk dashboard, Webhooks endpoint detail |

## Free tier and pricing

- Free up to **10,000 MAU** with all core features (UI components, organisations, social providers, webhook events).
- Beyond 10K MAU: **$25/mo flat + $0.02 per MAU above 10K**. So 50K MAU is $25 + ($0.02 × 40K) = $825/mo.
- SAML SSO is a paid add-on ($100+/mo per connection at the time of writing, verify on clerk.com/pricing).
- B2B SaaS Add-on (advanced organisations, custom roles per org) is also paid.

For small SaaS at sub-10K MAU, Clerk is effectively free forever. The killer scenario is greenfield products where shipping fast on hosted UI components is more valuable than the long-term cost curve.

## When to flip away from Clerk

- **MAU expected to cross 100K within 12 months** → flip to `/ro:workos` (1M MAU free, same vendor shape).
- **Non-engineer partner needs the hosted Admin Portal for full user management** → both Clerk and WorkOS have dashboards; if WorkOS Admin Portal's specific surface is needed, flip to `/ro:workos`.
- **Need to own the user table** for RLS, FK enforcement, EU data residency, custom fields beyond Clerk's metadata → flip to `/ro:better-auth`.
- **Custom auth flows** (unusual onboarding, multi-step verification, exotic providers) Clerk components do not bend to → flip to `/ro:better-auth`.

The flip path is documented per-target in the auth comparison page.

## Migration off later

If you flip away from Clerk to a self-hosted setup:

1. Use Clerk's User Backup API (or dashboard CSV export) to get every user. Save Clerk user_id, email, first/last name, email-verified flag.
2. Bulk-create accounts in the new system, keyed by email. Map `clerk_user_id` to the new internal ID in your domain tables.
3. Send a "we have moved, set a new password" email to all active users. Clerk does not export password hashes (security), so password-based users must reset on first login.
4. Run both systems in parallel for a week so users who miss the email can still get in via Clerk, then cut over.

Plan one engineer-week and a week of soft migration window. Same shape as the WorkOS migration plan.

## Safety

- Never put `CLERK_SECRET_KEY` or `CLERK_WEBHOOK_SECRET` in `~/.claude/.env`. Per-app secrets only. A leaked secret key lets anyone forge sessions for that one app.
- `CLERK_PUBLISHABLE_KEY` IS safe to ship to browsers (it is the bundle's identifier for which Clerk app to talk to), but treat it as per-app config rather than a global token.
- Webhook handlers must verify the svix signature before trusting the payload. The example above does this. Skipping the check lets anyone spoof user.deleted.
- The Clerk dashboard's "Convert test instance to production" is one-way. Use a fresh production instance from day one for any app you intend to ship; do not promote test data.

## See also

- `/ro:workos` for B2B-at-scale (100K+ MAU expected, partner needs WorkOS Admin Portal, near-term SAML SSO)
- `/ro:better-auth` for own-the-table cases (RLS, FKs, EU residency mandate, fully custom flows)
- `/ro:nango` when wiring third-party integrations (Nango sessions are scoped to your authenticated end-user)
- `/ro:stripe` when wiring payments (Stripe customers are linked to Clerk user IDs via `metadata.clerk_user_id`)
- `/ro:new-tanstack-app --auth` to scaffold a new app with Clerk pre-wired (default)
- `/ro:cf-ship` to ship after wiring
- Clerk docs: https://clerk.com/docs, use context7 (`/clerk/clerk-docs`) for current syntax
- Comparison page: `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`
