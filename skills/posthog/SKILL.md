---
name: posthog
description: Interact with PostHog (EU region) — install SDKs, query events, manage feature flags, run experiments, inspect insights. Use when user wants to track events, add analytics, create/toggle a feature flag, set up an A/B test, query product data, or wire PostHog into a TanStack Start app.
category: analytics
argument-hint: [install | flag <list|get|create|toggle> | experiment <list|get> | query <hogql> | event <recent>] [--project <id>]
allowed-tools: Bash(curl *) Bash(jq *) Bash(pnpm *) Read Write Edit
---

# PostHog

CLI-first PostHog ops via the public API (EU region, `eu.posthog.com`). Covers SDK install, feature flags, experiments, event queries, and HogQL.

## Usage

```
/ro:posthog install [--react|--node|--both]    # wire SDK into current app
/ro:posthog flag list                          # list all feature flags
/ro:posthog flag get <key>
/ro:posthog flag create <key> --rollout 50     # new boolean flag at 50%
/ro:posthog flag toggle <key>                  # enable/disable
/ro:posthog experiment list
/ro:posthog experiment get <id>
/ro:posthog query "SELECT event, count() FROM events GROUP BY event LIMIT 20"
/ro:posthog event recent [--event <name>]      # tail recent events
```

## Prerequisites

- Keys in `~/.claude/.env`:
  - `POSTHOG_PERSONAL_API_KEY` — all-access, for management API
  - `POSTHOG_HOST=https://eu.posthog.com` — management API host
  - `POSTHOG_INGEST_HOST=https://eu.i.posthog.com` — SDK ingest host
- `--project <id>` or `POSTHOG_PROJECT_ID` env var (numeric — look up via `list projects` below)

## Install — SDK wiring

### React (TanStack Start client)

```bash
pnpm add posthog-js
```

Create `src/lib/posthog.ts`. **Default is max-data capture** (replays, heatmaps, exceptions, performance, network bodies). For apps with auth or PII, see the "Safety" section below for the dial-down.

```ts
import posthog from "posthog-js";

if (typeof window !== "undefined") {
  posthog.init(import.meta.env.VITE_POSTHOG_PROJECT_API_KEY, {
    api_host: import.meta.env.VITE_POSTHOG_INGEST_HOST,
    person_profiles: "identified_only",
    capture_pageview: true,
    capture_pageleave: true,
    autocapture: true,
    disable_session_recording: false,
    session_recording: {
      maskAllInputs: false,
      recordCrossOriginIframes: true,
    },
    enable_heatmaps: true,
    capture_performance: true,
    capture_exceptions: true,
  });
}

export { posthog };
```

Expose in Vite env (`.dev.vars`):

```
VITE_POSTHOG_PROJECT_API_KEY=phc_...
VITE_POSTHOG_INGEST_HOST=https://eu.i.posthog.com
```

The **project API key** (`phc_...`, NOT the personal key) lives per-app — generate at `https://eu.posthog.com/project/<id>/settings`.

The SDK flags above pair with the project-level server switches below. Both sides need to be on, or the data won't flow.

### Project-level switches (management API)

Client SDK says "send this data"; project settings say "accept it". Flip both on install:

```bash
curl -s -X PATCH "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "session_recording_opt_in": true,
    "capture_console_log_opt_in": true,
    "capture_performance_opt_in": true,
    "autocapture_opt_out": false,
    "autocapture_exceptions_opt_in": true,
    "heatmaps_opt_in": true,
    "surveys_opt_in": true,
    "session_recording_sample_rate": "1.00",
    "session_recording_minimum_duration_milliseconds": 0,
    "session_recording_network_payload_capture_config": {"recordHeaders": true, "recordBody": true}
  }'
```

This is the **default for new apps**. Tone it down (see Safety) when adding auth, payments, or high traffic.

### Node / Server Functions (TanStack Start server)

```bash
pnpm add posthog-node
```

```ts
// src/lib/posthog-server.ts
import { PostHog } from "posthog-node";

export const posthog = new PostHog(process.env.POSTHOG_PROJECT_API_KEY!, {
  host: process.env.POSTHOG_INGEST_HOST ?? "https://eu.i.posthog.com",
});
```

Important: call `await posthog.shutdown()` at the end of each server function (Workers terminates quickly; unflushed events are lost).

## Launch-ready event instrumentation

Autocapture + pageviews are free, but **custom events are what make the launch plan measurable**. When `/ro:posthog install` runs, also wire a typed `track()` wrapper and fire events on the user paths that actually drive launch metrics.

### The typed `track()` wrapper (always ship this)

Autocapture misses anything behind a handler (e.g. `window.open(...)`), and direct `posthog.capture` calls have no type safety — a string typo silently creates a new event. Fix with a typed wrapper:

```ts
// src/lib/posthog.ts
export interface EventPayloads {
  share: {
    channel: 'x' | 'reddit' | 'whatsapp' | 'copy' | 'native'
    // Include the content identifier so launch funnels can slice by item:
    item_id: string | number | null
    item_date?: string
  }
  cta_clicked: { cta: string; location: string }
  form_submitted: { form: string; success: boolean }
  search_performed: { query_length: number; results: number }
  // ...app-specific events below
}

export function track<K extends keyof EventPayloads>(
  event: K,
  ...props: EventPayloads[K] extends undefined ? [] : [EventPayloads[K]]
): void {
  if (typeof window === 'undefined') return
  posthog.capture(event, props[0] as Record<string, unknown> | undefined)
}
```

Why a wrapper and not direct `posthog.capture`:

- **Type safety** — the `EventPayloads` map catches event-name typos at compile time.
- **No null-check** — `track()` is a no-op until init resolves, so handlers can call it unconditionally.
- **Grep-able** — `grep "track('share'" src` finds every call site in a second. Compare with `posthog.capture` which is used across many libs.
- **Refactor pressure** — renaming an event is a find/replace; in a 100-handler app this is load-bearing.

### The launch-week event checklist (fire these on day one)

Every consumer-facing launch needs these events instrumented **before the launch day**, not after. Missing events on day-one means the launch analytics story is blind when it matters most.

| Event | Fire on | Payload | Why it matters |
| --- | --- | --- | --- |
| `share` | Every share handler (native, X, Reddit, WhatsApp, copy-link, etc.) | `{ channel, item_id }` | Tells you which channel drives the viral loop. Autocapture misses these because they're `window.open` calls. |
| `cta_clicked` | Every primary button (sign up, buy, launch app, follow, install) | `{ cta, location }` | Funnel foundation. |
| `form_submitted` | Every form | `{ form, success }` | Conversion leaf. |
| `search_performed` | Every search box | `{ query_length, results }` | Learn what users can't find. Do NOT log the raw query unless no-PII policy says it's safe. |
| `content_viewed` | Content page open (blog, doc, product) | `{ type, slug }` | Compounds into "which content converts." |
| `feature_used` | Each distinctive feature action | `{ feature, ...context }` | The event that lets you say "X% of users hit this feature." |
| `error_shown` | Every user-visible error state | `{ error, boundary }` | Complements Sentry — catches UX errors that aren't exceptions. |

Project-specific additions (pattern: a verb + an object, present tense, snake_case):

- Daily-utility / content apps: `hint_revealed`, `detail_expanded`, `source_toggled`, `date_changed`.
- Commerce: `product_viewed`, `added_to_cart`, `checkout_started`, `checkout_completed`.
- B2B SaaS: `workspace_created`, `invite_sent`, `onboarding_step_completed`.

### Event naming rules

- **`snake_case`**, present-tense verbs with the object. `share` not `shared` or `ShareClick`.
- **Payload keys are snake_case too.** `puzzle_id` not `puzzleId`. PostHog's insight UI autocompletes snake_case properties better and matches HogQL conventions.
- **No PII in the event name or payload** unless explicitly whitelisted. `query_length` not `query`. Never put emails, UUIDs tied to PII, or free-text input in an event.
- **Version breaking changes.** If you change a payload shape, rename the event (e.g. `checkout_completed_v2`) rather than mutating history.

### Pre-launch verification

```bash
# Sanity-check ingest right before go-live (eu.posthog.com, per org default):
/ro:posthog event recent --event share
/ro:posthog query "SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 1 HOUR GROUP BY event ORDER BY count() DESC"
```

If a planned event doesn't appear, the handler isn't wired. Fix before launch day — debugging share-funnel attribution on the traffic spike is miserable.

### After-launch dashboards (fast setup)

In PostHog UI, spin up these three insights before launch, not after:

1. **Channel share table** — events `share`, group by `channel`, 7-day window. Tells you where the viral loop is actually working.
2. **Daily active users** — unique `$pageview` by day.
3. **Launch funnel** — `$pageview` → (first `feature_used`) → `share` or `cta_clicked`. Conversion rate + drop-off steps.

## Feature flags (management API)

All calls go to `${POSTHOG_HOST}/api/projects/<project-id>/feature_flags/` with `Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}`.

### List

```bash
curl -s "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/feature_flags/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  | jq '.results[] | {key, active, rollout_percentage: .filters.groups[0].rollout_percentage}'
```

### Create boolean flag at N% rollout

```bash
curl -s -X POST "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/feature_flags/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "new-checkout",
    "name": "New checkout flow",
    "active": true,
    "filters": { "groups": [{ "properties": [], "rollout_percentage": 50 }] }
  }'
```

### Toggle

```bash
# First GET to find the id, then PATCH:
curl -s -X PATCH "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/feature_flags/${FLAG_ID}/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"active": false}'
```

### Multivariate / experiment flag

Pass variants in `filters.multivariate.variants`. See experiments below.

## Experiments (A/B tests)

```bash
curl -s "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/experiments/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  | jq '.results[] | {name, feature_flag_key, start_date, end_date, parameters}'
```

Creating via API is possible but the dashboard is cleaner for setup; use API for **monitoring** (win probability, conversion deltas).

## HogQL queries

PostHog's SQL-like layer over events:

```bash
curl -s -X POST "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/query/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "kind": "HogQLQuery",
      "query": "SELECT event, count() FROM events WHERE timestamp > now() - INTERVAL 24 HOUR GROUP BY event ORDER BY count() DESC LIMIT 20"
    }
  }' | jq '.results'
```

## Recent events (sanity check ingest)

```bash
curl -s "${POSTHOG_HOST}/api/projects/${PROJECT_ID}/events/?limit=10" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  | jq '.results[] | {event, timestamp, distinct_id, properties: (.properties | {"$current_url", "$lib"})}'
```

## List projects (find your project ID)

```bash
curl -s "${POSTHOG_HOST}/api/projects/" \
  -H "Authorization: Bearer ${POSTHOG_PERSONAL_API_KEY}" \
  | jq '.results[] | {id, name, organization}'
```

## Env var summary

**Global (`~/.claude/.env`)**:
- `POSTHOG_PERSONAL_API_KEY` — for this skill's management calls
- `POSTHOG_SIMPLICITY_LABS_API_KEY` — org-scoped, can substitute for some ops
- `POSTHOG_HOST` — `https://eu.posthog.com`
- `POSTHOG_INGEST_HOST` — `https://eu.i.posthog.com`

**Per-app** (`.dev.vars` + wrangler secret):
- `POSTHOG_PROJECT_API_KEY` (`phc_...`) — client-side SDK init
- Also exposed to Vite as `VITE_POSTHOG_PROJECT_API_KEY` + `VITE_POSTHOG_INGEST_HOST`

## EU region note

Ronan's org is on the EU region. **Do not** use `us.posthog.com` or `app.posthog.com` — they'll 401. The skill hard-codes EU hosts in env for this reason.

## Safety

- Never expose `POSTHOG_PERSONAL_API_KEY` client-side. The client SDK only needs the project API key (`phc_...`), which is safe to ship.
- Flag creation / deletion is destructive for users in an active experiment — confirm with user before toggling a flag that's wired to a running experiment.
- `DELETE` on a flag cannot be undone from the API. Prefer `active: false` over delete.

### When to tone down the max-data default

The install default captures a lot on purpose (small side-project apps benefit from more signal). Dial back when:

- **Auth added** → flip `session_recording.maskAllInputs: true`. Default masks all input values; keeps passwords, emails, tokens out of replays.
- **Payments or sensitive forms** → drop `recordBody: true` from the project config (re-PATCH with `recordBody: false`). Add `ph-no-capture` class to sensitive DOM nodes. Use `maskTextSelector` for card numbers etc.
- **High traffic** → lower `session_recording_sample_rate` from `"1.00"` to `"0.10"` or less. Replays are the expensive product; 10% sampling still catches issues.
- **GDPR / regulated data** → flip `capture_performance_opt_in` and `capture_console_log_opt_in` to `false` if consoles might leak tokens; review `autocapture` for PII-bearing form fields.

## See also

- `/ro:sentry` — the other half of observability
- `/ro:new-tanstack-app` — scaffolds with posthog slot ready
- PostHog API docs: https://posthog.com/docs/api — use context7
