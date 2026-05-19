---
name: write-a-prd
description: Generate a PRD through an interactive interview. Defers to /ro:repo-mode for output target — `personal` repos publish the PRD as a GitHub issue (Matt Pocock's 7-section template with ready-for-agent label, agent-native repo pattern); `work` repos write to gitignored `.ralph/<name>/prd.md` so nothing leaks to the work GH/Jira/ADO project. First-run prompt picks the mode and persists per-repo; suggested default comes from the gh remote owner. Falls back to local prd.json when no gh remote exists. Use when user wants to write a PRD, plan a feature, create user stories, or start a Ralph project.
category: development
argument-hint: [--quick | --plan] [--target gh|local] [--label <label>] <feature-name>
allowed-tools: Read Write Edit Glob Grep Bash
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Write a PRD

Interactive interview that produces a PRD ready for slicing into vertical-slice issues and consumption by a Ralph-style or planner-worker autonomous loop.

## Output target — repo-mode aware

Resolution order (highest precedence first):

1. Explicit `--target gh|local` flag — always wins.
2. **Repo mode** — defer to `/ro:repo-mode` resolution. Per-repo `.claude/repo-mode`, then global `~/.claude/repo-mode`. If `personal` → `--target gh`. If `work` → `--target local` (no GH issue created — keeps the work GH/Jira/ADO project clean).
3. If repo mode is `unset`: run the **first-run prompt** described in `/ro:repo-mode` § "First-run prompt" (auto-suggest based on `gh repo view --json owner`, save to `.claude/repo-mode`, ask once whether to also save as `~/.claude/repo-mode` global default). This prompt fires exactly once per repo, then never again.
4. If repo mode resolves but no `gh` remote exists → force `--target local` regardless of mode (gh issue create would fail).

The resolver is the same 4-line snippet documented in `/ro:repo-mode`:

```bash
mode=""
[ -f .claude/repo-mode ] && mode="$(tr -d '[:space:]' < .claude/repo-mode)"
[ -z "$mode" ] && [ -f "$HOME/.claude/repo-mode" ] && mode="$(tr -d '[:space:]' < "$HOME/.claude/repo-mode")"
case "$mode" in personal|work) ;; *) mode="unset" ;; esac
```

When `--target gh` is selected, after the interview render the PRD content into the body template and publish via:

```bash
gh issue create \
  --title "<feature short title>" \
  --label "${LABEL:-ready-for-agent}" \
  --body-file -    # piped from the rendered template
```

Apply the project's `ready-for-agent` synonym if one is configured (e.g., `Sandcastle` in `mattpocock/course-video-manager`). Detect via `gh label list --json name,description --jq '.[] | select(.description | contains("agent"))'` or by checking `docs/agents/triage-labels.md` for the project-local label name. `--label <name>` flag overrides.

## GitHub-issue body template (Matt Pocock's 7-section PRD)

```md
## Problem Statement

The problem the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A long, numbered list. Each one shaped:

1. As a <actor>, I want <feature>, so that <benefit>
2. ...

Be extensive. Cover all aspects of the feature.

## Implementation Decisions

Modules to build or modify (favour deep modules). Interfaces. Technical clarifications. Architectural decisions. Schema changes. API contracts. Specific interactions.

Do NOT include file paths or code snippets — they go stale fast. Exception: a prototype-derived snippet (state machine, reducer, schema, type shape) that encodes a decision more precisely than prose can. Trim to the decision-rich parts.

## Testing Decisions

What makes a good test for this feature (external behaviour, not implementation). Which modules will be tested. Prior art for similar tests in the codebase.

> **Every slice this PRD generates inherits the close-the-loop test ACs (unit + integration + e2e + 30-second live smoke). Do not skip.** Captured at `[[close-the-loop-tests-acs]]` and enforced by `/ro:slice-into-issues` (which emits the `### Close-the-loop tests` subsection in every slice body) and `/ro:planner-worker` (which refuses to dispatch slices missing that section).

## Out of Scope

What this PRD explicitly does NOT cover.

## Further Notes

Anything else worth recording.
```

Output: the new GH issue number. Call it `$PARENT`. Hand off to `/ro:slice-into-issues` which will create child issues referencing `#$PARENT` via `## Parent\n\n#$PARENT`.

## Usage

```
/write-a-prd --quick my-feature                # Resolve target via /ro:repo-mode; personal -> GH issue, work -> .ralph/prd.json
/write-a-prd --plan my-feature                 # Same; --plan adds reviewable plan.md gate
/write-a-prd --target local my-feature         # Force local .ralph/prd.json regardless of repo-mode
/write-a-prd --target gh --label Sandcastle my-feature   # Force GH issue, custom label
/write-a-prd my-feature                        # Defaults to --quick + repo-mode resolution
```

## --quick Mode

### Step 1: Interview (5-8 questions via AskUserQuestion)

Ask these in order, one at a time. Adapt follow-ups based on answers.

1. **What** — "Describe the feature in 1-2 sentences. What does it do?"
2. **Why** — "What problem does this solve? What's the motivation?"
3. **Who** — "Who uses this? (developer, end-user, CLI user, automated system)"
4. **Scope** — "What's explicitly OUT of scope for this feature?"
5. **Acceptance** — "How do we know it's done? List the key acceptance criteria."
6. **Dependencies** — "Does this depend on anything existing? (files, APIs, libraries, other features)"
7. **Constraints** — "Any technical constraints or conventions to follow?" (skip if the user already covered this)
8. **Priority** — "What should be built first? Any ordering dependencies between pieces?"

### Step 2: Generate prd.json

Create `.ralph/prd.json` (create `.ralph/` directory if needed):

```json
{
  "project": "<project-name from package.json or directory name>",
  "branchName": "ralph/<feature-name>",
  "description": "<feature description from interview>",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short story title",
      "description": "As a <who>, I want <what> so that <why>",
      "acceptanceCriteria": [
        "Criterion from interview",
        "Another criterion"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Step 3: Review

Show the generated PRD to the user. Ask: "Does this look right? Any stories to add, remove, or reorder?"

Apply changes if requested, then confirm the final version.

## --plan Mode

### Step 1: Extended Interview (8-12 questions via AskUserQuestion)

Same questions as quick mode, plus:

9. **Architecture** — "How should this be structured? Any patterns to follow or avoid?"
10. **Risks** — "What could go wrong? What are you uncertain about?"
11. **Phases** — "Should this be delivered in phases? Any natural breakpoints?"
12. **Open questions** — "Anything you're unsure about that needs investigation first?"

### Step 2: Generate plan.md

Create `plans/<feature-name>.md` (create `plans/` directory if needed) with these sections:

- **Problem Statement** — why this feature exists
- **Proposed Solution** — high-level approach
- **Architecture Decisions** — key technical choices and rationale
- **Phases** — each phase has a goal and stories. Phase 1 is always the tracer bullet (thinnest end-to-end slice).
- **Risk Assessment** — table with Risk, Likelihood, Impact, Mitigation columns
- **Open Questions** — checklist of unknowns needing investigation

### Step 3: Review Loop

Present the plan. Ask: "Review this plan. What would you change?" Iterate until the user approves (possibly multiple rounds), then proceed.

### Step 4: Convert to prd.json

Convert the approved plan into `.ralph/prd.json` using the same format as quick mode. Flatten all phases into a single ordered story list, preserving priority order. Confirm: "Plan converted to `.ralph/prd.json` — ready for `/ralph`."

## Story Writing Rules

- **Vertical slices, not horizontal layers.** Each story cuts through UI, logic, and data. Never a story like "set up database" alone. Background: `llm-wiki-ai-research:vertical-slices-tracer-bullets`.
- **Independently demoable.** After each story, you can show something working.
- **Tracer bullet first.** The first story should be the thinnest possible end-to-end path.
- **Foundational/risky slices first.** Validate unknowns early, not last.
- **One Ralph iteration per story.** If a story feels too big for one context window, split it. Background: `llm-wiki-ai-research:smart-zone-dumb-zone`.
- **Use "As a X, I want Y so that Z" format** for story descriptions.
- **IDs are sequential:** US-001, US-002, US-003, etc.
- **Priority matches order:** story with priority 1 is built first.

## Module map (recommended companion step)

If the PRD is non-trivial, run `/slice-into-issues` immediately after this skill. That step proposes a module map (favouring deep modules per `llm-wiki-ai-research:deep-modules-for-ai`) before emitting one issue file per slice into `.ralph/issues/`. The pair (write-a-prd + slice-into-issues) is the canonical input to `/ralph --kanban` and to `/matt-pocock-coding-workflow`.

## Web-app baseline checklist

When the PRD describes an app with a web UI, an authenticated user, or an HTTP API, you MUST emit the following stories (or mark "N/A — <reason>" if genuinely skippable). Otherwise the gap surfaces mid-build:

1. **US-000 Bootstrap** — repo + scaffold + quality stack + first green deploy. DoD includes a health probe against the deployed URL, not just green CI.
2. **Sign-out** — explicit "WHEN user clicks sign-out THE system SHALL end the session and redirect to /". Sign-out is a user-visible feature; it gets its own story even if the auth provider gives you a button for free.
3. **Lazy auth-mirror** — if auth uses webhooks (Clerk / Auth0 / etc.), include a story for the cold-start path before the webhook fires.
4. **API discoverability** — OpenAPI doc at `/api/openapi/json` + rendered viewer (Scalar / Swagger / Redoc) at `/api-docs`.
5. **API client collection** — Bruno (or Postman) committed with one request per public route, env files for local + prod.
6. **Integration test layer** — handler-level tests with an in-memory or test-container DB; at minimum one per data-mutating endpoint.
7. **CI env injection** — the workflow materialises the dev-server env file (`.dev.vars`, `.env.local`) from CI secrets before any job runs the dev server.
8. **Per-story deploy verification** — each shipping story's DoD: the deployed URL returns 200 from `/api/health` AND the new route is reachable. Green CI alone is not enough.
9. **Lazy reconciliation for external state** — if you mirror state from an external service (Nango, Stripe, Clerk, GitHub), the read endpoint reconciles from the source on every request. Webhook = fast path; reconcile-on-read = correct path.
10. **Onboarding checklist** — when relevant (B2B SaaS with multi-step activation), replace empty-state Home with a gamified checklist driven by server-observed events. See `/onboarding-flow` skill + `[[onboarding-checklist-ux]]` canon.
11. **Share assets (favicon + app icons + OG + Twitter card)** — favicon set (.ico, .svg, apple-touch), PWA manifest icons, static OG fallback, dynamic per-URL OG route, OpenGraph + Twitter card meta tags, JSON-LD application schema. Default favicons + missing OG previews look broken when the app is shared. See `/share-assets` skill.
12. **Worker bundle-size budget** — If deploying to Cloudflare Workers, every story DoD includes "wrangler deploy --dry-run target=production passes". Free-tier ceiling 3 MiB gzipped, paid 10 MiB. wasm + inlined fonts/images are the usual culprits.

Ask the user up-front "is this a web app, a CLI, or a library?" — if web, run through the checklist before generating prd.json.
