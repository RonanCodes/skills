---
name: nango
description: Wire Nango cloud into a TanStack Start + Cloudflare Workers app for OAuth + token-refresh + proxy across third-party APIs. Install, env config, server SDK, Connect UI session, Shopify recipe, Google Ads recipe, webhook verification. Use when user wants to add Nango, wire integrations, connect Shopify, Shopify OAuth, Google Ads OAuth, OAuth broker, integration platform, or connect a merchant's store to a TanStack Start + D1 + WorkOS app.
category: integrations
argument-hint: [install | add-shopify | add-google-ads | add-webhook | add-connect-ui]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(curl *) Bash(git *) Read Write Edit
---

# Nango

Wire [Nango cloud](https://www.nango.dev) into a TanStack Start + Drizzle + D1 app on Cloudflare Workers. Nango handles OAuth + token refresh + a proxy. You still write the GraphQL queries against Shopify, Google Ads, and the rest. The trade is: skip months of OAuth plumbing per provider, pay $0 to $50 to $500 a month depending on connection count.

This is the canonical integration broker for the user's stack as of 2026-04-30. For the full broker-vs-native trade-off analysis see `llm-wiki-research/wiki/comparisons/integration-brokers.md`.

## Usage

```
/ro:nango install                      # initial wiring (server SDK + env + connection helper)
/ro:nango add-connect-ui               # client Connect UI session for merchant onboarding
/ro:nango add-shopify                  # Shopify provider config + scopes + GraphQL Admin recipe
/ro:nango add-google-ads               # Google Ads provider config + scopes + GAQL recipe
/ro:nango add-webhook                  # /api/webhooks/nango with signature verification
```

## Prerequisites

- A TanStack Start app (`/ro:new-tanstack-app` or `/ro:migrate-to-tanstack`)
- Auth wired (`/ro:workos` or `/ro:better-auth`). Connect UI sessions are scoped to your authenticated end-user
- A Nango account (free, sign up at nango.dev), one Integration created in the dashboard per provider you connect

## Pricing tiers (verify on nango.dev/pricing before billing decisions)

| Plan | Monthly | Connections | Proxy requests | Connection overage |
|---|---|---|---|---|
| Free | $0 | 10 | included | n/a |
| Starter | $50+ | 20 | 200K | $1 each |
| Growth | $500+ | 100 | 1M | $1 each |
| Enterprise | custom | custom | custom | custom |

A connection is one merchant's authorisation for one provider (one Shopify + one Google Ads = two connections). At 5 pilot merchants on 2 providers each, you sit on Free or just into Starter. Phase-2 trigger: customer #5, where the bake-off vs Composio is worth the day.

## Install flow

### 1. Install dependencies

```bash
pnpm add @nangohq/node @nangohq/frontend
```

`@nangohq/node` is the server SDK (Workers-compatible, fetch-based). `@nangohq/frontend` opens the Connect UI from the browser using a session token your server mints.

### 2. Per-app env vars

```bash
# .dev.vars
NANGO_SECRET_KEY=<server secret from nango.dev/dev/environment-settings>
NANGO_PUBLIC_KEY=<public key from same page, safe to ship to browser>
NANGO_HOST=https://api.nango.dev   # optional, default
```

Production secrets:

```bash
wrangler secret put NANGO_SECRET_KEY
wrangler secret put NANGO_PUBLIC_KEY        # safe to put in vars too if you prefer
```

Add the env shape to your `Env` type, regenerate with `wrangler types`.

### 3. Server SDK module, `src/lib/nango.ts`

The Workers runtime has no `process.env`, so configure programmatically from the request `env` binding.

```ts
import { Nango } from '@nangohq/node';

let cached: { env: string; client: Nango } | null = null;

export function getNango(env: Env): Nango {
  if (cached?.env === env.NANGO_SECRET_KEY) return cached.client;
  const client = new Nango({
    secretKey: env.NANGO_SECRET_KEY,
    host: env.NANGO_HOST ?? 'https://api.nango.dev',
  });
  cached = { env: env.NANGO_SECRET_KEY, client };
  return client;
}
```

### 4. Connection retrieval helper

A connection is identified by `providerConfigKey` (the integration ID you set in the Nango dashboard, e.g. `shopify`, `google-ads`) plus `connectionId` (typically your merchant's user or organisation ID).

```ts
// src/lib/integrations.ts
import { getNango } from '@/lib/nango';

export async function getAccessToken(env: Env, providerConfigKey: string, connectionId: string) {
  const nango = getNango(env);
  const conn = await nango.getConnection(providerConfigKey, connectionId);
  return conn.credentials.access_token;
}

export async function callProvider(
  env: Env,
  providerConfigKey: string,
  connectionId: string,
  request: { method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'; endpoint: string; data?: unknown; params?: Record<string, string | number> },
) {
  const nango = getNango(env);
  switch (request.method) {
    case 'GET':    return nango.get({    providerConfigKey, connectionId, endpoint: request.endpoint, params: request.params });
    case 'POST':   return nango.post({   providerConfigKey, connectionId, endpoint: request.endpoint, data: request.data });
    case 'PUT':    return nango.put({    providerConfigKey, connectionId, endpoint: request.endpoint, data: request.data });
    case 'PATCH':  return nango.patch({  providerConfigKey, connectionId, endpoint: request.endpoint, data: request.data });
    case 'DELETE': return nango.delete({ providerConfigKey, connectionId, endpoint: request.endpoint });
  }
}
```

`nango.getConnection()` auto-refreshes the access token if it has expired. `nango.get/post/...` is the proxy: same auto-refresh, plus Nango injects auth and rate-limit handling.

You can also fetch the token and call the API directly. Use the proxy when you want Nango's retries + auth injection; call directly when you need a feature Nango's proxy doesn't model (custom headers, streaming responses, GraphQL operation names).

## add-connect-ui

The Connect UI is a hosted page that walks the merchant through the OAuth dance. Your server mints a session token; the client opens the UI with that token; on success the UI returns the new `connectionId` to your client.

### Server: mint a session, `src/routes/api/integrations/connect-session.ts`

```ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getNango } from '@/lib/nango';
import { requireSession } from '@/lib/auth-server';

export const ServerRoute = createServerFileRoute('/api/integrations/connect-session').methods({
  POST: async ({ request, context }) => {
    const user = await requireSession();
    const body = await request.json() as { providerConfigKey: string };

    const nango = getNango(context.cloudflare.env);
    const session = await nango.createConnectSession({
      end_user: { id: user.userId, email: user.email },
      organization: user.organizationId ? { id: user.organizationId } : undefined,
      allowed_integrations: [body.providerConfigKey],
    });

    return Response.json({ token: session.data.token });
  },
});
```

### Client: open the UI, `src/components/connect-button.tsx`

```tsx
import Nango from '@nangohq/frontend';
import { useState } from 'react';

export function ConnectButton({ providerConfigKey, label }: { providerConfigKey: string; label: string }) {
  const [busy, setBusy] = useState(false);

  const onClick = async () => {
    setBusy(true);
    try {
      const res = await fetch('/api/integrations/connect-session', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ providerConfigKey }),
      });
      const { token } = await res.json() as { token: string };

      const nango = new Nango({ connectSessionToken: token });
      nango.openConnectUI({
        onEvent: (event) => {
          if (event.type === 'connect') {
            window.location.assign(`/dashboard/integrations/${providerConfigKey}/connected`);
          }
        },
      });
    } finally {
      setBusy(false);
    }
  };

  return <button onClick={onClick} disabled={busy}>{label}</button>;
}
```

The session token is short-lived. Mint a fresh one each time the merchant clicks the button.

## add-shopify

### 1. Create the integration in the Nango dashboard

Settings → Integrations → New → Shopify. Provider config key: `shopify`. Paste the Shopify Custom App's API key + secret. Add scopes: `read_products`, `read_orders`, `read_customers`, `read_inventory`, plus whatever else you need.

### 2. Connect a merchant

Use `<ConnectButton providerConfigKey="shopify" label="Connect your Shopify store" />`. The Connect UI prompts for the shop subdomain (e.g. `acme.myshopify.com`), the merchant approves, you get a `connectionId`.

### 3. Call Shopify GraphQL Admin

```ts
// src/lib/integrations/shopify.ts
import { callProvider } from '@/lib/integrations';

export async function getShopifyOrders(env: Env, merchantId: string) {
  const result = await callProvider(env, 'shopify', merchantId, {
    method: 'POST',
    endpoint: '/admin/api/2025-04/graphql.json',
    data: {
      query: `
        query GetRecentOrders {
          orders(first: 50, sortKey: CREATED_AT, reverse: true) {
            edges { node { id name createdAt totalPriceSet { shopMoney { amount currencyCode } } } }
          }
        }
      `,
    },
  });
  return result.data.data.orders.edges.map((e: any) => e.node);
}
```

The Shopify API version (`2025-04`) is set in the URL and pins your queries to a stable schema for 12 months. Bump on a known cadence, not silently.

### 4. Webhook signature verification (Shopify-specific)

Shopify webhooks are signed with HMAC-SHA256 against the shop's webhook secret, NOT the Nango secret. Nango does not handle this for you; you do it directly. Register the webhook through the Shopify Admin or `/admin/api/.../webhooks.json` with your Worker URL.

```ts
// src/routes/api/webhooks/shopify.ts
import { createServerFileRoute } from '@tanstack/react-start/server';

async function verifyShopifyHmac(secret: string, body: string, sig: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return expected === sig;
}

export const ServerRoute = createServerFileRoute('/api/webhooks/shopify').methods({
  POST: async ({ request, context }) => {
    const env = context.cloudflare.env;
    const sig = request.headers.get('x-shopify-hmac-sha256');
    if (!sig) return new Response('Missing signature', { status: 400 });

    const body = await request.text();
    const valid = await verifyShopifyHmac(env.SHOPIFY_WEBHOOK_SECRET, body, sig);
    if (!valid) return new Response('Bad signature', { status: 401 });

    const event = JSON.parse(body);
    // dispatch on x-shopify-topic header (orders/create, orders/updated, etc.)
    return new Response('ok');
  },
});
```

`SHOPIFY_WEBHOOK_SECRET` is per-merchant if you use shop-specific webhooks, or per-app if you register at the app level. The dashboard makes this clear; default to per-merchant for least-privilege.

## add-google-ads

Google Ads is the harder of the two and the gating step is NOT in your code.

### 1. Get a Google Ads developer token (the wall-clock blocker)

Apply for **Standard Access** through the Google Ads Manager Account (MCC) you intend to operate from. Apply through Taskforce's MCC, not Simplicity's, because Standard Access reviewers expect to see an established agency footprint with real customer accounts already linked.

The published SLA is 10 business days; the review backlog has been extended past that as of February 2026 per the Google Ads Developers blog. Plan four weeks. Test Access works for development against your own MCC immediately, but you cannot call against external customer accounts until Standard Access lands.

### 2. Create the integration in the Nango dashboard

Settings → Integrations → New → Google Ads. Provider config key: `google-ads`. Paste the OAuth client ID + secret you got from the Google Cloud Console (OAuth 2.0 Client ID, type Web Application). Add scope `https://www.googleapis.com/auth/adwords`.

### 3. Connect a merchant

Use `<ConnectButton providerConfigKey="google-ads" label="Connect your Google Ads account" />`. The merchant signs in to Google, picks the customer account they want to authorise. You get a `connectionId`. The merchant's Google Ads customer ID is in the connection metadata.

### 4. Call the Google Ads REST API

The Google Ads API is gRPC-first, but they ship a REST surface that works in Workers. Always pass `login-customer-id` (your MCC's customer ID, dashes stripped) and `developer-token` headers; pass the merchant's `customer-id` in the URL.

```ts
// src/lib/integrations/google-ads.ts
import { getAccessToken } from '@/lib/integrations';

const API_VERSION = 'v17';

export async function runGAQL(env: Env, merchantId: string, customerId: string, query: string) {
  const token = await getAccessToken(env, 'google-ads', merchantId);
  const res = await fetch(
    `https://googleads.googleapis.com/${API_VERSION}/customers/${customerId}/googleAds:search`,
    {
      method: 'POST',
      headers: {
        'authorization': `Bearer ${token}`,
        'developer-token': env.GOOGLE_ADS_DEVELOPER_TOKEN,
        'login-customer-id': env.GOOGLE_ADS_LOGIN_CUSTOMER_ID,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!res.ok) throw new Error(`Google Ads ${res.status}: ${await res.text()}`);
  return res.json();
}

export async function getCampaignPerformance(env: Env, merchantId: string, customerId: string) {
  return runGAQL(env, merchantId, customerId, `
    SELECT
      campaign.id,
      campaign.name,
      campaign.status,
      metrics.impressions,
      metrics.clicks,
      metrics.cost_micros,
      metrics.conversions
    FROM campaign
    WHERE segments.date DURING LAST_7_DAYS
    ORDER BY metrics.cost_micros DESC
  `);
}
```

`cost_micros` is in micros (1M micros = 1 unit of currency). Always divide by 1_000_000 before showing money to a human.

`GOOGLE_ADS_DEVELOPER_TOKEN` and `GOOGLE_ADS_LOGIN_CUSTOMER_ID` are per-app, not per-merchant. The login-customer-id is your MCC, the customer-id in the URL is the merchant's. Mistake the two and the call fails opaquely.

## add-webhook

Nango itself can push events when a connection is created, refreshed, or errors. This is separate from Shopify webhooks (handled above per-provider).

```ts
// src/routes/api/webhooks/nango.ts
import { createServerFileRoute } from '@tanstack/react-start/server';
import { getNango } from '@/lib/nango';

export const ServerRoute = createServerFileRoute('/api/webhooks/nango').methods({
  POST: async ({ request, context }) => {
    const nango = getNango(context.cloudflare.env);
    const body = await request.text();
    const headers: Record<string, string> = {};
    request.headers.forEach((v, k) => { headers[k] = v; });

    const valid = nango.verifyIncomingWebhookRequest(JSON.parse(body), headers);
    if (!valid) return new Response('Bad signature', { status: 401 });

    const event = JSON.parse(body);
    switch (event.type) {
      case 'auth':
        // event.connectionId is the new connection. Persist the link.
        break;
      case 'sync':
        // a Nango sync completed
        break;
      case 'forward':
        // a third-party webhook proxied via Nango (alternative to per-provider routes)
        break;
    }
    return new Response('ok');
  },
});
```

Configure the webhook URL in the Nango dashboard (Settings → Webhooks). The signing secret used by `verifyIncomingWebhookRequest` is your `NANGO_SECRET_KEY`.

## Workers compatibility

Nango cloud is the only Workers-friendly path. The self-hosted Nango stack runs Node + Postgres + Redis + Elasticsearch and needs a real VM (Fly, Railway, EC2). If a hard self-host requirement lands, your app continues to use `@nangohq/node` against your own host instead of `https://api.nango.dev`. Set `NANGO_HOST=https://nango.your-domain.com` in env.

Cloud's EU residency is not publicly documented as of 2026-04-30. If a Dutch merchant asks where tokens live, verify with Nango sales (sales@nango.dev) before answering.

## Migration off later

The good news: third-party API calls already happen against the real APIs (Shopify GraphQL, Google Ads REST). Migrating off Nango means rebuilding the OAuth dance + token refresh per provider, plus replacing the proxy. That is roughly one engineer-week per provider plus tests. Plan for three weeks if you have Shopify + Google Ads + one more.

## Env var summary (per-app)

| Var | Where | Source |
|---|---|---|
| `NANGO_SECRET_KEY` | `.dev.vars` + wrangler secret | Nango dashboard, Environment Settings |
| `NANGO_PUBLIC_KEY` | `.dev.vars` + wrangler secret (or vars) | Same page |
| `NANGO_HOST` | optional, default `https://api.nango.dev` | only if self-hosting |
| `SHOPIFY_WEBHOOK_SECRET` | wrangler secret (after add-shopify) | Shopify Admin, per-shop or per-app |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | wrangler secret (after add-google-ads) | Google Ads MCC, after Standard Access |
| `GOOGLE_ADS_LOGIN_CUSTOMER_ID` | wrangler secret | Your MCC's customer ID, dashes stripped |

## Safety

- `NANGO_SECRET_KEY` lets the holder read every connection's tokens. Per-app secret only, never in `~/.claude/.env`. Rotate on any team change.
- `verifyIncomingWebhookRequest` MUST be called on every Nango webhook before trusting the payload. Skipping it lets anyone spoof connection events.
- Shopify webhooks use a different secret (per-shop or per-app, set in Shopify Admin). Do not confuse them with the Nango secret. The HMAC verification is yours to write, not Nango's.
- Google Ads developer token is rate-limited at the token level. One token across many customers is fine; one token across many apps is not. Do not share the developer token across unrelated products.
- The `login-customer-id` header is your MCC, the URL `customer-id` is the merchant. Mistakes here are hard to debug because Google returns generic 404s.

## See also

- `/ro:workos` for auth (must be wired before merchants can connect integrations)
- `/ro:new-tanstack-app` to scaffold the app first
- `/ro:cf-ship` to ship after wiring
- Nango docs: https://nango.dev/docs, dashboard: https://app.nango.dev
- Comparison page: `llm-wiki-research/wiki/comparisons/integration-brokers.md`
- Phase-2 trigger: customer #5 → bake-off vs Composio (MCP-native alternative) before paying the first Starter invoice
