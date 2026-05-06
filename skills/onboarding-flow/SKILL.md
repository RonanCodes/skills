---
name: onboarding-flow
description: Scaffold a gamified onboarding checklist for a TanStack Start + Clerk + D1 app. Generates the D1 state model, server-event-driven completion handlers, a Home-page checklist component, and a PostHog activation funnel. Mirrors the "persistent dashboard widget + event-driven auto-tick" pattern documented in the llm-wiki canon. Use when starting a new app or when an existing app's empty Home dashboard needs to become an activation surface.
category: development
argument-hint: [--steps step1,step2,...] [--scaffold-route /dashboard] [--state-table onboarding_step] <project-name>
allowed-tools: Read Write Edit Glob Grep Bash AskUserQuestion
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Onboarding Flow

Generates a working gamified-onboarding implementation for a TanStack Start + Clerk + D1 app. Output: a D1 migration, server-side event handlers, a React checklist component, and a PostHog funnel definition. Source: `[[onboarding-checklist-ux]]` in `llm-wiki-research` for the patterns this skill encodes.

## When to use

- Greenfield TanStack Start app where Home is currently a blank "connect a source" page.
- Existing app where the activation rate is low because users land on an empty dashboard with no clear next action.
- Any product that wants to track an activation funnel across discrete user actions.

## When NOT to use

- CLI tools (no UI to checklist).
- Apps with one obvious next action (a single big CTA already does the job).
- Multi-tenant team-onboarding (this skill targets single-user activation; team flows are richer and need a different pattern).

## What this scaffolds

1. **D1 schema** — `onboarding_step` table keyed (user_id, step_key) + Drizzle migration.
2. **Server-side state API** — `GET /api/onboarding/state` returns `{ steps, total, completed, percent }` from D1.
3. **Step-completion event handlers** — small functions that upsert a step row when a real event fires (a connection lands, a tool runs, a chat sends, etc.). Idempotent on (user_id, step_key); first-completion timestamp is canonical.
4. **PostHog event emission** — every completion fires `onboarding_step_completed` with `{user_id, org_id, step_key, sequence_number, time_since_signup_seconds}`.
5. **OnboardingChecklist React component** — shadcn Card + Badge + lucide CheckCircle/Circle, progress meter, per-step CTAs, skip-for-session, axe-passing.
6. **Home-page conditional render** — incomplete checklist when any step pending, populated dashboard once all complete (with a small dismissable celebration banner).
7. **(Optional) Clerk publicMetadata mirror** — a single boolean `onboardingCompleted` on the Clerk user, written when the last step ticks. Lets edge auth check completion without a D1 round-trip.

## Patterns enforced (from the canon)

- **Persistent dashboard widget**, not a first-run modal. Modals lose users who came to do real work.
- **Event-driven auto-tick** — the system observes the action; users don't click "mark complete." (Highlight.io moved to this after their sequential flow stalled.)
- **3 to 5 hard prerequisites + alternative paths** — Dataforce's seven steps work because steps 3 to 7 are alternative routes to the same aha moment, not seven separate prerequisites.
- **Free-roam, not linear** — any incomplete step is openable; no artificial "you must do step 2 before step 3" gate unless there's a real data dependency.
- **State lives server-side** (D1), with a single Clerk `publicMetadata` mirror for fast edge routing. localStorage is for UI niceties (collapsed/expanded), never for completion truth.
- **Pre-tick the signup step** — the first item is always already-checked (Zeigarnik / endowed-progress effect).
- **Celebrate then fade** at 100 percent — banner appears for one session, dismissable, replaced on next visit by the populated dashboard.

## Anti-patterns refused

- First-run modal that blocks the dashboard.
- User-clicked "Mark complete" buttons (it's a TODO list, not an activation tool).
- localStorage as the completion store (cross-device breaks, clearing cache breaks).
- More than 5 hard prerequisites without framing 3+ as alternative paths.
- Auto-dismissing the checklist on first 100-percent reach so it can never be reopened.
- A linear gate that locks step N until step N-1 is done.

## Usage

```
/onboarding-flow --steps connect-source,run-tool,send-chat,install-host my-app
/onboarding-flow --steps step-a,step-b,step-c,step-d --scaffold-route /home my-app
```

If `--steps` is omitted, the skill asks via AskUserQuestion for the activation moments.

## Step 1 — Confirm the steps interactively

Use AskUserQuestion to gather:

1. **The aha moment** — "What's the one thing a user must experience for this product to click?"
2. **Hard prerequisites** — "What 1-3 actions must happen before the aha is reachable?"
3. **Alternative paths** — "What 2-4 framings of the aha do you want to surface as separate steps?" (e.g. for Dataforce: install-claude-code, install-claude-desktop, install-chatgpt, run-local-mcp are four alternative paths to the same aha.)
4. **Telemetry sink** — PostHog (default), Mixpanel, or none.
5. **Skip behavior** — skip-for-session (default per canon) vs no-skip (anti-pattern, refuse) vs skip-permanent.

Confirm the resulting step list before scaffolding.

## Step 2 — Generate the schema

Write a Drizzle migration:

```ts
// drizzle/00NN_onboarding_step.sql (auto-generated)
CREATE TABLE onboarding_step (
  id text PRIMARY KEY,
  user_id text NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  step_key text NOT NULL,
  completed_at integer NOT NULL,
  payload text,
  created_at integer NOT NULL DEFAULT (unixepoch())
);
CREATE UNIQUE INDEX onboarding_step_user_key_idx ON onboarding_step(user_id, step_key);
```

Plus the Drizzle TS:

```ts
export const onboardingStep = sqliteTable('onboarding_step', {
  id: text('id').primaryKey(),
  userId: text('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  stepKey: text('step_key', { enum: STEP_KEYS }).notNull(),
  completedAt: integer('completed_at', { mode: 'timestamp' }).notNull(),
  payload: text('payload', { mode: 'json' }),
  createdAt: integer('created_at', { mode: 'timestamp' }).notNull().default(sql`(unixepoch())`),
}, (t) => ({
  userKeyIdx: uniqueIndex('onboarding_step_user_key_idx').on(t.userId, t.stepKey),
}))
```

## Step 3 — Generate the lazy upsert helper

Mirrors `ensureUserMirror` and `reconcileConnectionsForUser`:

```ts
// src/lib/onboarding-mirror.ts
export async function markStepComplete(
  db: AnySQLiteDb,
  userId: string,
  stepKey: StepKey,
  payload?: Record<string, unknown>,
): Promise<{ alreadyComplete: boolean; sequence: number }> {
  // SELECT existing; if found, return { alreadyComplete: true }
  // Otherwise INSERT with completedAt = now, sequence = current count + 1
  // Idempotent on (user_id, step_key)
}
```

Pure function, no `cloudflare:workers` imports, integration-testable with in-memory better-sqlite3 (the test helper from PR #12 in dataforce repo).

## Step 4 — Wire event sources

For each step in the user's list, identify the existing handler that signals completion and add a `markStepComplete` call inside the same transaction. Examples:

- Nango webhook (connection landed) → `markStepComplete(db, userId, 'connect-shopify')`
- `POST /api/playground/run` 200 path → `markStepComplete(db, userId, 'run-tool')`
- `POST /api/chat` first-stream-chunk → `markStepComplete(db, userId, 'send-chat')`
- MCP `tools/list` arrival → detect host via User-Agent, `markStepComplete(db, userId, 'install-<host>')`

If the action doesn't exist yet, the skill emits a TODO comment in the planned handler instead of a fake call.

## Step 5 — PostHog event emission

Inside `markStepComplete`, after the insert succeeds, capture:

```ts
posthog.capture(userId, 'onboarding_step_completed', {
  step_key: stepKey,
  sequence_number: sequence,
  time_since_signup_seconds: nowSeconds - userCreatedAtSeconds,
  org_id: orgId,
})
```

Then write a saved insight in PostHog: a Funnel insight with steps in the order the user defined. The skill can't auto-create the insight, but emits a `docs/posthog-setup.md` note with the exact filter config.

## Step 6 — OnboardingChecklist component

```tsx
// src/components/onboarding/checklist.tsx
'use client'
export function OnboardingChecklist({ steps, total, completed }: OnboardingState) {
  const percent = Math.round((completed / total) * 100)
  return (
    <Card data-testid="onboarding-checklist" aria-label="Onboarding checklist">
      <ProgressMeter value={percent} />
      <ul role="list">
        {steps.map((s) => <ChecklistItem key={s.key} step={s} />)}
      </ul>
    </Card>
  )
}
```

Each `ChecklistItem` is a Card with title, description, primary CTA (`<Link to={s.cta}>{s.ctaLabel}</Link>`), status badge (`<Badge variant={done ? 'default' : s.skipped ? 'secondary' : 'outline'}>`), and a "Skip for now" link that hides the item from local React Query cache only.

Accessibility: every step has `aria-label`, the progress meter is `role="progressbar"`, tab order matches visual order, and axe-core passes (verify in the e2e suite).

## Step 7 — Home-page conditional render

```tsx
// src/routes/dashboard.tsx
function Home() {
  const { data: state } = useQuery(['onboarding-state'], fetchOnboardingState)
  if (!state) return <Loading />
  if (state.completed === state.total) return <PopulatedDashboard celebrationBanner />
  return <OnboardingChecklist {...state} />
}
```

Note: the populated dashboard (once it exists; in dataforce this is US-014 from v1) is a separate component. The skill doesn't generate it; it just wires the conditional.

## Step 8 — Tests

The skill emits:

- `tests/integration/onboarding-state.test.ts` — table shape, idempotent upsert, read-through.
- `tests/integration/onboarding-events.test.ts` — one test per event source.
- `e2e/onboarding-home.spec.ts` — incomplete state renders checklist, all-complete state renders populated dashboard, skip-for-now hides the step in-session, every CTA navigates.

All using the existing in-memory better-sqlite3 helper.

## Verification before claiming done

- `pnpm test:integration` passes.
- `pnpm test:e2e` passes (new auth-control + onboarding suites).
- Visiting `/dashboard` as a fresh user shows the checklist.
- Completing one action in another tab makes the relevant step tick on refresh.
- `pnpm quality` green.

## What this skill explicitly does NOT do

- Decide WHICH steps to use. The user defines them; the skill scaffolds.
- Style the component beyond shadcn defaults. Visual polish is the user's call.
- Ship the underlying actions (the connect flow, the chat handler, etc.). It only wires `markStepComplete` into existing handlers.
- Replace an existing onboarding system. This skill is for greenfield or empty-state scaffolds.

## Related

- `[[onboarding-checklist-ux]]` — the canon page this skill encodes (research, patterns, anti-patterns)
- `[[ideal-tech-setup]]` § Greenfield Spec Baseline — onboarding belongs as a first-class story in any greenfield spec
- `/generate-spec` — emits an onboarding US-* automatically when scaffolding a new web app
- `/ralph` — runs the resulting PRD
