---
name: setup-logging
description: Set up (or audit) the observability stack in a TanStack Start + Cloudflare Workers app so it is "diagnosable by default" — structured logging (logtape) with a request context carrying trace_id + userId + tenant/orgId, a trace_id propagated FE→BE→logs→Sentry→PostHog, Cloudflare Workers observability enabled, and Sentry + PostHog wired. Two modes: `setup` (wire it into an app) and `audit` (check an existing app + report gaps). Use when scaffolding a new app, when a bug couldn't be diagnosed because logs were missing, or when the user asks to "set up logging / observability / make this app diagnosable / audit logging". Pairs with /ro:diagnose (which consumes these logs) and is wired into /ro:new-tanstack-app + /ro:new-app.
category: project-setup
argument-hint: [audit <repo-path> | setup]
allowed-tools: Bash(*) Read Grep Glob Edit Write AskUserQuestion
---

# setup-logging — make an app diagnosable by default

A repo is **diagnosable** when a bug can be traced from one id across every layer. This skill installs (mode `setup`) or verifies (mode `audit`) that baseline. It is the supply side of `/ro:diagnose` (the demand side).

## The baseline (what "correct" means)

1. **Structured logging** — logtape (`@logtape/logtape`), JSON formatter, **console sink** (so `wrangler tail` + CF Workers Logs see it) + a **Sentry sink at warning+** (alerts, with breadcrumbs). One `log(category)` helper.
2. **Request log context** — `AsyncLocalStorage` (`withRequestLogContext`) carrying `trace_id`, `userId`, and the tenant id (`orgId`/`accountId`) so EVERY log line in a request is correlatable. Identity set as soon as it's resolved (so even early returns carry it).
3. **trace_id end-to-end** — a UUIDv7 minted per FE action, sent as `x-<app>-trace-id` on every `/api/*` fetch, read (or minted) at the worker boundary, threaded into the log context + `Sentry.setTag` + a PostHog property. (Reference: dataforce #288.)
4. **Cloudflare observability ON** — `"observability": { "enabled": true }` in `wrangler.jsonc` (historical Workers Logs; without it `wrangler tail` is live-only).
5. **Sentry + PostHog wired** (EU region for Simplicity apps) so the three log sources `/ro:diagnose` sweeps all exist.

## Two gotchas that silently break logging (learned the hard way, dataforce #352)

- **Durable Objects (and any non-route entrypoint) must call `configureLogger(env)` themselves.** logtape config is per-isolate; a DO that calls `log(...)` without configuring has no sink → logs vanish silently.
- **Don't set the `configured` guard before the async `configure()` resolves.** A pattern like `configured = true; void configure({...})` permanently disables logging if `configure` is slow or throws. **Await** `configure()` and set the guard only on success.
- **Verify, don't assume.** After setup, run `wrangler tail` and confirm a real log line appears. "We added a log" ≠ "the log emits."

## Mode: audit

```bash
bash ~/Dev/ronan-skills/skills/setup-logging/scripts/audit-logging.sh <repo-path>
```

Greps the repo + reports a pass/fail checklist against the baseline above (logtape present, console sink, request context, trace_id propagation, `observability.enabled`, Sentry, PostHog, DO-configureLogger, guard-race). For each FAIL, propose the concrete fix; for high-value gaps, offer to implement. End with a one-line "diagnosable: yes/partial/no".

The script is a heuristic sweep — confirm findings by reading the flagged files, and for the two gotchas, actually trace whether logs reach a sink (a `wrangler tail` smoke is the ground truth).

## Mode: setup

Wire the baseline into the app, mirroring the dataforce implementation (`src/lib/logger.ts` + `src/lib/trace-id.ts` + `withRequestLogContext` + `wrangler.jsonc observability`). Steps:
1. Add `@logtape/logtape` (+ `@logtape/sentry` if Sentry is present). Create `src/lib/logger.ts`: `configureLogger(env)` (await `configure`, set guard on success), `withRequestLogContext`, `setRequestLogIdentity`, `log(category)`.
2. trace_id: `src/lib/trace-id.ts` (UUIDv7 + header const), FE fetch wrapper, worker-boundary resolve, thread into context + Sentry + PostHog.
3. `wrangler.jsonc`: add `"observability": { "enabled": true }`.
4. Ensure EVERY entrypoint (routes AND Durable Objects/queues/cron) calls `configureLogger(env)`.
5. Smoke: `wrangler tail` + hit an endpoint → confirm a structured line appears.

## See also
- `/ro:diagnose` — consumes these logs to debug.
- `/ro:new-tanstack-app`, `/ro:new-app` — call this during scaffolding.
- `/ro:sentry`, `/ro:posthog` — per-tool wiring.

## Provenance
- 2026-05-24 — created after dataforce chat bugs couldn't be diagnosed because the structured logs we'd added never emitted (DO never called `configureLogger`; the `configured` guard was set before the async `configure()` resolved). Codifies the baseline + the two silent-failure gotchas as a setup + audit skill.
