---
name: diagnose
description: Diagnose a runtime bug by sweeping the observability logs (Cloudflare Workers logs, Sentry, PostHog) using the shared trace_id, and if the logs don't capture what's needed, ADD structured logging at the failure point + in the request context, deploy (remote) or run locally, and have the user reproduce. Use whenever the user mentions logs, a bug, an issue, "why did X fail / not work", "check the logs", "it works on desktop but not mobile", a stack trace, an error code, or a flaky/intermittent failure. Auto-pick this before guessing at a fix.
category: workflow
argument-hint: [<what's failing> | --local | --remote]
allowed-tools: Bash(*) Read Grep Glob WebFetch AskUserQuestion Edit Write
---

# diagnose — log-driven debugging (sweep, then instrument)

When the user reports a bug, an error, or "why did X fail", do NOT jump to a speculative fix. Run this loop:

## 1. Hypothesis from the code (fast)
Grep the failing path. Form a concrete hypothesis about WHERE and WHY. Note the exact signal you'd need from logs to confirm (an id, a resolved value, a branch taken).

## 2. Sweep the logs (the three sources)
Source creds from `~/.claude/.env` (see `/ro:env` for which keys). Correlate with the **trace_id** if the app has it (the `x-dataforce-trace-id` pattern), and pivot to the **PostHog session replay** for front-end repros.

- **Cloudflare Workers logs** — only if `observability: { enabled: true }` in `wrangler.jsonc` (else `wrangler tail` is LIVE-only; you can't see the past).
  `wrangler tail` for a live repro; for history use the observability telemetry API:
  `POST https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/observability/telemetry/query` (filter by worker + time + a needle like the error code).
- **Sentry** (EU): `GET https://de.sentry.io/api/0/projects/<org>/<project>/issues/?statsPeriod=24h` with `Authorization: Bearer $SENTRY_AUTH_TOKEN`. NOTE: handled `{ ok:false }` error envelopes are NOT exceptions — they won't be in Sentry. Only thrown/captured errors are.
- **PostHog** (EU): `GET https://eu.posthog.com/api/projects/<id>/events/?limit=N` with `Authorization: Bearer $POSTHOG_PERSONAL_API_KEY`. Find the user's event (e.g. `chat_message_sent`) near the failure time; grab `$session_id` → replay URL `https://eu.posthog.com/project/<id>/replay/<session_id>`.

## 3. Decide: do the logs pinpoint it?
- **Yes** → fix the root cause, add a regression test, ship.
- **No (the needed field isn't logged)** → this is the common case. Go to step 4.

## 4. Instrument, then reproduce
Add **structured logging** that captures exactly the signal you needed in step 1:
- Put the load-bearing identifiers in the **request log context** (so every line in the request carries them) — e.g. `userId`, `orgId`, `trace_id`. Then add a targeted `log(...).info('<event>', { ...resolved values, branch taken })` at the decision point, and a `warn` at the failure point (error code + scope).
- Keep it greppable and PII-careful (ids, not secrets).

Then choose where to reproduce:
- **Remote** (default when the bug was hit on the deployed app — e.g. "on mobile", a prod URL, a real user): merge + deploy, then ask the user to **re-run the exact flow**, then re-sweep the logs to confirm. The bug lives where it was observed.
- **Local** (when it's a dev/local-only repro or cheaper to reproduce): `pnpm dev` (tee logs to `.dev-logs/`), reproduce locally, read the logs. Suggest this when the failure isn't environment-specific.

Ask the user which, if it's genuinely ambiguous; otherwise infer (mobile/prod → remote).

## 5. Confirm + close
After the re-run, read the new logs, confirm the hypothesis, ship the real fix (often the instrumentation PR already contains it), and keep the useful logs.

## Build-in mechanism (every repo should have this)
A repo is "diagnosable" when it has, by default:
1. A **request-scoped trace_id** threaded FE→BE→logs→Sentry→PostHog (so one id correlates all three sources).
2. **Structured logging** (logtape or similar) with a request context carrying `trace_id` + `userId` + tenant/`orgId`.
3. **Cloudflare `observability: { enabled: true }`** (historical Workers logs), Sentry, and PostHog wired.
When diagnosing in a repo that lacks these, propose adding them — it's the difference between "add a log and redeploy" (minutes) and "guess". Reference the dataforce trace_id implementation (issue #288) as the template.

## See also
- `/ro:env` — which credential for which log source.
- `/ro:posthog`, `/ro:sentry` — deeper per-tool operations.
- `/ro:cf-ship` — deploy the instrumentation so a remote repro can be re-run.

## Provenance
- 2026-05-23 — created after a "Shopify tool works on desktop, fails on mobile" report where the root cause (org resolved via the Clerk active org) couldn't be confirmed because the resolved org was never logged. Codifies: sweep CF/Sentry/PostHog first, and when the needed signal isn't logged, instrument + redeploy + re-run rather than guess.
