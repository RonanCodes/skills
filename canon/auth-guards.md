# Canon: auth guards on login-gated pages

**Rule:** every page that requires a logged-in user MUST have a server-side route guard that redirects unauthenticated users to sign-in. A signed-out visitor must never be able to *render* a gated page (even briefly). This is non-negotiable for any product we build.

## Why (the failure this prevents)

API-level 401s are NOT enough. If the page renders for a signed-out user and only its data fetches 401/500, the user sees a broken page (or worse, a 500 — dataforce #356, where `/onboarding/role` rendered signed-out and its API threw an unhandled 500). The PAGE itself must refuse to render and redirect.

Client-side `<Protect>` / conditional UI hiding is also not enough — it's trivially bypassed. Gate the route **server-side in `beforeLoad`**; use client-side `<Protect>` only to hide UI *within* an already-gated page.

## The pattern (TanStack Start + Clerk)

A shared guard, applied per-route (or via a pathless layout group if the router supports it cleanly so it can't drift):

```ts
// src/lib/require-auth.ts — resolve userId server-side; redirect if absent.
export const requireAuth = async () => {
  const { userId } = await auth()            // server-side
  if (!userId) {
    throw redirect({ to: '/sign-in', search: { redirect_url: location.href } })
  }
}
// per route:
export const Route = createFileRoute('/dashboard')({ beforeLoad: requireAuth, ... })
```

Sign-in must honour `redirect_url` so the user lands back where they were.

## What's gated vs public (decide explicitly per route)

- **Gated:** anything rendering authed data or the app shell — dashboard, connections, chat, settings, onboarding, install/PAT flows, admin (admin adds a role check on top).
- **Public:** marketing/landing, `/sign-in`, `/sign-up`, docs (if public), privacy/terms, OAuth `.well-known`/authorize/token, API routes that self-authenticate.

Per-route is a deliberate choice — when adding a route, classify it. Don't let "I forgot to add the guard" be the default.

## Audit (run when building/reviewing any app)

```bash
# routes that render the authed app shell / call user data but have no beforeLoad guard:
grep -rL 'beforeLoad' src/routes/*.tsx | xargs grep -lE 'AppShell|resolveAuth|useUser|/api/(user|pat|chat|connections)' 2>/dev/null
```
Every hit is a candidate gap — verify it's intentionally public or add the guard.

## Lesson (provenance)

dataforce shipped a route-guard pass (#328) that covered the obvious app pages but MISSED `/onboarding/*` and `/mcp/install/*` (#356). Both rendered signed-out and broke. The fix was to guard them — but the durable fix is this canon: **classify every route as gated or public, and never let a gated page render for a signed-out user.** New apps get this from `/ro:new-tanstack-app` + the auth skills; verify with the audit above.
