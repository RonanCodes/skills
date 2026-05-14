---
name: clerk
description: Wire Clerk into a TanStack Start app on Cloudflare Workers using the dedicated @clerk/tanstack-react-start package. Install, env config, clerkMiddleware in src/start.ts, ClerkProvider in __root.tsx, drop-in UI components (SignIn, SignUp, UserButton, OrganizationSwitcher), server-side auth() helper for createServerFn, useUser / useAuth hooks for client routes, Drizzle shadow user table, webhook signature verification, organisations + multi-tenancy, plus a role taxonomy (superadmin / staff / member) and requireRole() helper for gating admin routes like /styleguide. Default auth pick for small SaaS where speed-to-market and out-of-the-box UI matter. Use when user wants to add Clerk, add auth, wire login, sign-in component, user button, organisation switcher, small SaaS auth, fastest auth, Clerk middleware, hosted auth UI, or role-based access control.
category: auth
argument-hint: [install | add-organizations | add-roles | add-webhook | open-dashboard] [--social github,google]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(open *) Read Write Edit
---

# Clerk

Wire [Clerk](https://clerk.com) into a TanStack Start + Drizzle + D1 app on Cloudflare Workers. Hosted sign-in UI with drop-in React components, server-side session verification via the dedicated `@clerk/tanstack-react-start` package, organisations as first-class for B2B.

This is the canonical auth pick for the user's stack as of 2026-05-05. Optimised for small SaaS where speed-to-first-working-sign-in matters more than scale features. For B2B-at-scale (100K+ MAU expected, partner needs hosted Admin Portal, near-term SAML SSO), use `/ro:workos`. For own-the-table semantics (RLS / FKs / EU residency mandate / fully custom flows), use `/ro:better-auth`. Comparisons: `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`.

**Why the dedicated TanStack package:** as of late 2025, Clerk ships `@clerk/tanstack-react-start` which integrates into TanStack Start's request middleware pipeline natively. It replaces the older `@clerk/clerk-react` + `@clerk/backend` two-package setup. The dedicated package handles env loading without requiring the `VITE_` prefix dance, exposes a clean `auth()` helper for `createServerFn` handlers, and a `clerkClient()` for fetching full user data server-side.

## Usage

```
/ro:clerk install                              # initial wiring (env + middleware + provider + sign-in routes + roles helper)
/ro:clerk install --social github,google       # + GitHub + Google providers
/ro:clerk add-organizations                    # multi-tenant orgs + OrganizationSwitcher
/ro:clerk add-roles                            # role helper only (superadmin / staff / member + requireRole)
/ro:clerk add-webhook                          # /api/webhooks/clerk with svix signature verification
/ro:clerk open-dashboard                       # open the Clerk dashboard for this app
```

`add-roles` runs automatically inside `install` — it's exposed separately for retrofitting an app that already has Clerk wired but no role helper.

## Prerequisites

- A TanStack Start app (`/ro:new-tanstack-app` or `/ro:migrate-to-tanstack`)
- Drizzle + D1 already wired (`src/db/schema.ts`, `wrangler.toml` with `[[d1_databases]]`)
- A Clerk account (free, sign up at clerk.com), one Application created in the dashboard

## Install flow

### 1. Install dependencies

```bash
pnpm add @clerk/tanstack-react-start
pnpm add svix     # for webhook signature verification (only if using add-webhook)
```

The single `@clerk/tanstack-react-start` package ships drop-in components (client side), the `clerkMiddleware()` request integration, and `auth()` + `clerkClient()` helpers (server side). Runs in Workers, no Node-only APIs.

### 2. Per-app env vars

```bash
# .dev.vars (local dev) and .env (build-time fallback)
CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
CLERK_WEBHOOK_SECRET=whsec_...      # only after add-webhook
```

Both keys come from the Clerk dashboard, API Keys page. Production keys (`pk_live_`, `sk_live_`) are separate from test keys. **No `VITE_` prefix needed** with the new package; it handles client / server exposure internally.

Production secrets:

```bash
wrangler secret put CLERK_PUBLISHABLE_KEY
wrangler secret put CLERK_SECRET_KEY
wrangler secret put CLERK_WEBHOOK_SECRET     # only after add-webhook
```

### 3. Add `clerkMiddleware()` to the start instance, `src/start.ts`

```ts
import { clerkMiddleware } from '@clerk/tanstack-react-start';
import { createStart } from '@tanstack/react-start';

export const startInstance = createStart(() => {
  return {
    requestMiddleware: [clerkMiddleware()],
  };
});
```

`clerkMiddleware()` runs before every request, reads the session cookie or `Authorization: Bearer` header, verifies the JWT against Clerk's JWKS (cached automatically), and populates the auth context that `auth()` reads downstream. No round-trip to Clerk's servers per request.

### 4. Wrap the app with `<ClerkProvider>`, `src/routes/__root.tsx`

```tsx
import { ClerkProvider } from '@clerk/tanstack-react-start';
import { HeadContent, Scripts, createRootRoute } from '@tanstack/react-router';
import { TanStackRouterDevtools } from '@tanstack/react-router-devtools';
import Header from '../components/Header';
import appCss from '../styles.css?url';

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      { title: 'Your App' },
    ],
    links: [{ rel: 'stylesheet', href: appCss }],
  }),
  shellComponent: RootDocument,
});

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        <ClerkProvider>
          <Header />
          {children}
        </ClerkProvider>
        <TanStackRouterDevtools />
        <Scripts />
      </body>
    </html>
  );
}
```

Note: `<ClerkProvider>` does **not** take a `publishableKey` prop with this package. The middleware (Step 3) injects the publishable key into the SSR HTML, and the provider reads it from there. One less thing to wire.

### 5. Drop-in sign-in route, `src/routes/sign-in.tsx`

```tsx
import { createFileRoute } from '@tanstack/react-router';
import { SignIn } from '@clerk/tanstack-react-start';

export const Route = createFileRoute('/sign-in')({
  component: () => (
    <div className="flex min-h-screen items-center justify-center">
      <SignIn routing="path" path="/sign-in" signUpUrl="/sign-up" forceRedirectUrl="/dashboard" />
    </div>
  ),
});
```

Mirror with `src/routes/sign-up.tsx` using `<SignUp />`. That is the entire sign-in UI. No callback handler to write, Clerk's hosted flow handles OAuth round-trips and email verification.

### 6. UserButton in the app shell

```tsx
import { UserButton, SignedIn, SignedOut, SignInButton } from '@clerk/tanstack-react-start';

export function AppHeader() {
  return (
    <header className="flex items-center justify-between p-4">
      <Logo />
      <SignedIn>
        <UserButton afterSignOutUrl="/" />
      </SignedIn>
      <SignedOut>
        <SignInButton />
      </SignedOut>
    </header>
  );
}
```

`<UserButton />` renders the avatar with a menu including profile, account settings, sign-out, and (if orgs enabled) org switcher. `<SignedIn>` and `<SignedOut>` are control components that render their children only when the user is in the matching state. This is the headline DX argument for Clerk vs the alternatives.

### 7. Protect a server function with `auth()`

```ts
// src/routes/dashboard.tsx
import { createFileRoute, redirect } from '@tanstack/react-router';
import { createServerFn } from '@tanstack/react-start';
import { auth } from '@clerk/tanstack-react-start/server';

const requireSessionFn = createServerFn({ method: 'GET' }).handler(async () => {
  const { isAuthenticated, userId, orgId, orgRole } = await auth();
  if (!isAuthenticated) {
    throw redirect({ to: '/sign-in' });
  }
  return { userId, orgId, orgRole };
});

export const Route = createFileRoute('/dashboard')({
  beforeLoad: () => requireSessionFn(),
  loader: ({ context }) => context,
  component: DashboardPage,
});
```

The session shape from `auth()` flows to the page via `Route.useLoaderData()` or `Route.useRouteContext()`. The middleware (Step 3) makes `auth()` cheap; it reads from already-verified context, no per-call JWT verification.

## Reading user data

Three patterns depending on where you need the data, server vs client, and how much you need.

### Server function with full user data

When the EARS criterion needs more than the `userId` (e.g. email, first name, image URL):

```tsx
// src/routes/dashboard.tsx
import { createFileRoute, redirect } from '@tanstack/react-router';
import { createServerFn } from '@tanstack/react-start';
import { auth, clerkClient } from '@clerk/tanstack-react-start/server';

const dashboardLoadFn = createServerFn().handler(async () => {
  const { isAuthenticated, userId } = await auth();
  if (!isAuthenticated) throw redirect({ to: '/sign-in' });
  const user = await clerkClient().users.getUser(userId);
  return {
    userId,
    firstName: user.firstName,
    email: user.emailAddresses[0]?.emailAddress,
  };
});

export const Route = createFileRoute('/dashboard')({
  beforeLoad: () => dashboardLoadFn(),
  loader: ({ context }) => context,
  component: Dashboard,
});

function Dashboard() {
  const { firstName } = Route.useLoaderData();
  return <h1>Welcome, {firstName}</h1>;
}
```

### API route handler

For raw HTTP API endpoints (e.g. webhook receivers, REST endpoints called from outside the app):

```ts
// src/routes/api/example.ts
import { createFileRoute } from '@tanstack/react-router';
import { auth, clerkClient } from '@clerk/tanstack-react-start/server';
import { json } from '@tanstack/react-start';

export const ServerRoute = createFileRoute('/api/example')({
  server: {
    handlers: {
      GET: async () => {
        const { isAuthenticated, userId } = await auth();
        if (!isAuthenticated) {
          return new Response('Unauthorized', { status: 401 });
        }
        const user = await clerkClient().users.getUser(userId);
        return json({ user });
      },
    },
  },
});
```

### Client hooks: `useAuth()` and `useUser()`

Inside React components:

```tsx
import { useAuth, useUser } from '@clerk/tanstack-react-start';

function ApiCallExample() {
  const { isLoaded, isSignedIn, userId, getToken } = useAuth();

  const callExternalApi = async () => {
    const token = await getToken();
    return fetch('https://api.example.com/data', {
      headers: { Authorization: `Bearer ${token}` },
    });
  };

  if (!isLoaded) return <div>Loading...</div>;
  if (!isSignedIn) return <div>Sign in to view</div>;
  return <button onClick={callExternalApi}>Fetch</button>;
}

function ProfileExample() {
  const { isLoaded, isSignedIn, user } = useUser();
  if (!isLoaded) return <div>Loading...</div>;
  if (!isSignedIn) return <div>Sign in to view</div>;
  return <div>Hello, {user.firstName}</div>;
}
```

`useAuth()` is light: token + auth state + IDs. Use when you only need to gate UI or get a session token. `useUser()` is heavier: full user object. Use sparingly; prefer fetching server-side via `clerkClient()` and passing through a route loader.

## --social github,google

Clerk handles social providers in the dashboard, no app code change. Open the Application page, navigate to "User & Authentication" → "Social Connections", toggle GitHub or Google, paste the OAuth client ID + secret you got from each provider's developer console.

Callback URLs to register on the provider side are shown in the Clerk dashboard (per-provider, with copy buttons).

## add-organizations

Clerk Organizations are first-class. Each `Organization` has Members, Roles, Invitations. Free up to 10K MAU.

Add the switcher anywhere in the shell:

```tsx
import { OrganizationSwitcher, UserButton } from '@clerk/tanstack-react-start';

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

The active org propagates to the server-side `auth()` return as `orgId` and `orgRole`. Org-scoped data fetching:

```ts
const { orgId } = await auth();
if (!orgId) throw new Response('No active org', { status: 400 });
const rows = await db.select().from(merchants).where(eq(merchants.orgId, orgId));
```

Client-side hooks: `useOrganization()` returns the current org and membership, `useOrganizationList()` for switching, `useUser()` for the user object.

For per-org RBAC, use Clerk's built-in roles (`org:admin`, `org:member`, custom). `auth().orgRole` returns the active member's role, and Clerk's `<Protect>` component gates UI:

```tsx
import { Protect } from '@clerk/tanstack-react-start';

<Protect role="org:admin">
  <DangerZone />
</Protect>
```

## add-roles — role taxonomy + `requireRole()` helper

Three-tier role model, Clerk-native where possible. Used to gate admin routes like `/styleguide` and any future admin panel.

| Role | Source of truth | Who it's for | Why this shape |
|---|---|---|---|
| `superadmin` | Hardcoded `SUPERADMIN_EMAILS` constant in `src/lib/auth/roles.ts` | One or two product owners (e.g. `admin@simplicitylabs.io`) | Belt-and-braces. Even if someone edits Clerk metadata or org roles directly in the dashboard, they cannot grant themselves superadmin without a code change + deploy. The hardcoded set is the recovery surface if Clerk itself is compromised |
| `staff` | Clerk org custom role `org:staff` | Employees / contractors who need admin-panel access but should not be able to alter billing, owners, or roles | Lives in Clerk so promotions/revocations are dashboard operations, no deploy needed |
| `member` | Clerk default org role `org:member` | Paying customers / regular signed-in users | Default. Anyone who completes sign-up lands here. No admin routes |

`admin` (mid-tier with delegation rights) is intentionally **skipped** for now — add it later when there's a real need to delegate staff promotion away from the superadmin. Most small SaaS never need this tier.

### Configure the `org:staff` role in Clerk dashboard

One-time setup, per environment (test + production each need it):

1. Open `https://dashboard.clerk.com` → your application → **Organizations** → **Roles**
2. Click **Create role** → key `org:staff`, name `Staff`, description `Internal team — admin panel access, no billing or role-management writes`
3. Permissions: at minimum select `org:sys_memberships:read` so staff can see other org members. Skip `org:sys_memberships:manage` (that's the delegation power you'd grant a future `org:admin`)
4. Save. The role is now assignable from the Members tab of any org

`org:member` exists out of the box and needs no configuration.

### Emit `src/lib/auth/roles.ts`

```ts
import { auth, clerkClient } from '@clerk/tanstack-react-start/server';

// Hardcoded recovery list. Edits to this list require a deploy — that's the point.
// Add the second person ONLY when there's a documented reason; superadmin is meant to be rare.
export const SUPERADMIN_EMAILS = ['admin@simplicitylabs.io'] as const;

export type Role = 'superadmin' | 'staff' | 'member';

export async function getRole(): Promise<Role | null> {
  const { isAuthenticated, userId, orgRole } = await auth();
  if (!isAuthenticated || !userId) return null;

  // Superadmin check: primary email against hardcoded set.
  // Fetched server-side via clerkClient so a forged metadata edit can't bypass this.
  const user = await clerkClient().users.getUser(userId);
  const primaryEmail = user.emailAddresses.find(
    (e) => e.id === user.primaryEmailAddressId,
  )?.emailAddress;
  if (primaryEmail && (SUPERADMIN_EMAILS as readonly string[]).includes(primaryEmail)) {
    return 'superadmin';
  }

  // Clerk org custom role check.
  if (orgRole === 'org:staff') return 'staff';
  return 'member';
}

export async function requireRole(...allowed: Role[]): Promise<Role> {
  const role = await getRole();
  if (!role || !allowed.includes(role)) {
    // 404, not 401/403: don't leak the existence of admin routes to unauthed visitors.
    throw new Response('Not Found', { status: 404 });
  }
  return role;
}
```

The 404 (vs redirect to sign-in or a 403) is deliberate. From a signed-out browser, `/styleguide` should look identical to `/anything-that-doesnt-exist`. Anyone scraping for admin surfaces gets no signal.

### Use it in a route

```tsx
// src/routes/styleguide.tsx
import { createFileRoute } from '@tanstack/react-router';
import { createServerFn } from '@tanstack/react-start';
import { requireRole } from '@/lib/auth/roles';

const guardFn = createServerFn({ method: 'GET' }).handler(async () => {
  return await requireRole('superadmin', 'staff');
});

export const Route = createFileRoute('/styleguide')({
  beforeLoad: () => guardFn(),
  component: StyleguidePage,
});

function StyleguidePage() {
  // tokens + typography + shadcn component matrix render here
  return <div>Style guide</div>;
}
```

The same pattern wraps any future admin route. The `requireRole()` call is the only line that changes per surface.

### Why a code-side helper instead of relying on Clerk's `<Protect>` alone

`<Protect role="org:staff">` is great for UI hiding (don't render a button) but it's client-side and trivially bypassed by a determined user. `requireRole()` runs server-side in `beforeLoad`, gates the route before any data leaks, and combines org role + hardcoded superadmin in one place. Use both: `requireRole()` to gate the route, `<Protect>` to hide UI surfaces within an already-gated page.

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
import { createFileRoute } from '@tanstack/react-router';
import { Webhook } from 'svix';
import { db } from '@/db';
import { users, organizations } from '@/db/schema';
import { eq } from 'drizzle-orm';

export const ServerRoute = createFileRoute('/api/webhooks/clerk')({
  server: {
    handlers: {
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
        let event: { type: string; data: any };
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
    },
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

No `VITE_` prefix; the new `@clerk/tanstack-react-start` package handles client-side exposure internally.

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

- Never put `CLERK_SECRET_KEY` or `CLERK_WEBHOOK_SECRET` in a committed `.env`. Per-app secrets only. A leaked secret key lets anyone forge sessions for that one app.
- `CLERK_PUBLISHABLE_KEY` IS safe to ship to browsers (it is the bundle's identifier for which Clerk app to talk to), but treat it as per-app config rather than a global token.
- Webhook handlers must verify the svix signature before trusting the payload. The example above does this. Skipping the check lets anyone spoof user.deleted.
- The Clerk dashboard's "Convert test instance to production" is one-way. Use a fresh production instance from day one for any app you intend to ship; do not promote test data.

## See also

- `/ro:workos` for B2B-at-scale (100K+ MAU expected, partner needs WorkOS Admin Portal, near-term SAML SSO)
- `/ro:better-auth` for own-the-table cases (RLS, FKs, EU residency mandate, fully custom flows)
- `/ro:nango` when wiring third-party integrations (Nango sessions are scoped to your authenticated end-user)
- `/ro:stripe` when wiring payments (Stripe customers are linked to Clerk user IDs via `metadata.clerk_user_id`)
- `/ro:design-system-create --showcase` to scaffold the `/styleguide` route that consumes `requireRole('superadmin', 'staff')`
- `/ro:new-tanstack-app --auth` to scaffold a new app with Clerk pre-wired (default)
- `/ro:cf-ship` to ship after wiring
- Clerk TanStack Start docs: https://clerk.com/docs/tanstack-react-start, especially the user-data reading guide at /guides/users/reading
- Comparison page: `llm-wiki-research/wiki/comparisons/auth-three-way-deep-dive.md`
