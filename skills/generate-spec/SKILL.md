---
name: generate-spec
description: Generate a spec-driven-development spec for a feature or whole product. Two modes — fresh (interview-driven greenfield) or from-codebase (analyses an existing repo). Outputs versioned markdown to docs/specs/ with EARS-format requirements, mermaid diagrams, and inline ADRs. Optional PDF render and vault mirror. Use when starting a new project, capturing the current state of an existing codebase, or before a major phase of work.
category: development
argument-hint: [--mode fresh|from-codebase] [--pdf] [--vault <name>] [--repo <path>] <feature-or-project-name>
allowed-tools: Read Write Edit Glob Grep Bash
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Generate Spec

Produces a single `spec.md` per generation, versioned by date and mode, in the target codebase's `docs/specs/`. The spec is the executable contract: stories use EARS format, decisions are inline ADRs, and the plan slots straight into `/ralph`.

Sister skills: `/compare-specs` (diff two specs) and `/compare-codebase-to-spec` (drift audit). Render to PDF via the llm-wiki `/generate pdf` skill.

## Usage

```
/generate-spec --mode fresh <name>                   # greenfield, interactive interview
/generate-spec --mode from-codebase <name>           # analyse existing repo at cwd
/generate-spec --mode from-codebase --repo <path>    # analyse a specific repo
/generate-spec --pdf <name>                          # also render PDF
/generate-spec --vault <vault-short> <name>          # mirror summary into a vault
```

`<name>` is kebab-case. Defaults to repo's package.json name or directory name.

## Output

Path: `<repo>/docs/specs/spec-v<N>-<mode>-YYYY-MM-DD.md`

Where `<N>` auto-increments by counting existing `spec-v*.md` files. Mode is `fresh` or `from-codebase`. Always create `docs/specs/` if missing.

If `--pdf`, also render `<repo>/docs/specs/spec-v<N>-<mode>-YYYY-MM-DD.pdf` by invoking `/generate pdf` against the markdown file.

If `--vault <vault-short>`, write a summary stub to `vaults/llm-wiki-<vault-short>/wiki/specs/<name>-spec-v<N>.md` with a cross-vault link back to the source spec.

## --mode fresh

Interview the user via AskUserQuestion. Ask one question at a time. Adapt based on answers. Cover all 10 sections of the template.

Question order:

1. **Outcomes** — "What does success look like? Name 2-3 user-visible outcomes and 1 business outcome."
2. **Users** — "Who uses this? Roles, scale, technical level."
3. **Scope** — "What's explicitly IN scope for v1? What's OUT?"
4. **Constraints** — "Tech, business, regulatory, time. Anything non-negotiable?"
5. **Constitution** — "What principles should never be broken? (3-7 items)"
6. **User stories** — "Walk me through the main flows. I'll convert to EARS format."
7. **Architecture** — "Stack? Components? Data shape? Anything to draw?"
8. **Decisions** — "What have you already decided and why? (chose X over Y because Z)"
9. **Plan** — "How would you phase delivery? Tracer bullet first."
10. **Verification** — "How is each story accepted? Test, demo, metric."
11. **Open questions** — "What's still unknown?"

Then write the spec using the template below. Show it to the user. Ask: "Look right? Anything to revise before we save?"

## --mode from-codebase

Read the repo and infer each section. Do not invent. Mark inferred items with a `(inferred)` tag in the spec so the user can validate.

Inference order (use grep, glob, and Read):

1. **Identity & stack** — `package.json`, `pnpm-lock.yaml`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `wrangler.jsonc`. Read `README.md`, `ARCHITECTURE.md`, `TECH_CHOICES.md` if present.
2. **Outcomes & scope** — README "Why I built this" / "What it does" sections; `package.json` description.
3. **Constitution & decisions** — `TECH_CHOICES.md`, `DESIGN_SYSTEM.md`, `ARCHITECTURE.md`. Treat each "we chose X because Y" as an inline ADR.
4. **Users** — README user-facing sections; landing page copy if present.
5. **User stories** — Convert observed features (routes, components, user flows) to EARS-format stories. Source: `src/routes/**`, `src/pages/**`, `src/components/**`, exposed CLI commands, public API endpoints.
6. **Architecture** — Build a C4 container diagram from the dependency graph. Sequence diagrams for key flows (auth, primary user action, data fetch). Data model from `drizzle/`, `prisma/`, `migrations/`, `models/`.
7. **Plan** — Read `.ralph/prd.json` if present, otherwise leave a single milestone "v1 (current)" and list shipped stories.
8. **Verification** — From `tests/`, `e2e/`, CI config. Each story → linked test or "no test (gap)".
9. **Constraints** — From `wrangler.jsonc` runtime, `package.json` engines, env var requirements, DPA/compliance docs in `docs/`.
10. **Open questions** — TODO/FIXME grep, items in ROADMAP.md or open issues if `gh` is available.

If `--vault <name>` is set, read `vaults/llm-wiki-<name>/wiki/entities/project-<repo-name>.md`, the launch plan, and recent session notes. Treat vault notes as supplementary context, codebase as primary.

## Spec Template (the 10 sections)

````markdown
---
title: <Project> Spec
version: v<N>
date: YYYY-MM-DD
mode: fresh | from-codebase
status: draft | reviewed | accepted | superseded
repo: <path or git url>
related-vault: <vault-short or empty>
supersedes: <previous version or empty>
---

# <Project> Spec, v<N>

> One-sentence summary of what this spec covers.

## 1. Constitution

Non-negotiable principles. If a future change violates one of these, the principle wins or the constitution is amended explicitly.

- **<Principle>** — <one-line rationale>

## 2. Outcomes

What success looks like.

| Outcome | Audience | How we measure |
|---|---|---|
| <user-visible outcome> | <user role> | <metric or signal> |

## 3. Scope

| In scope (v<N>) | Out of scope |
|---|---|
| <feature> | <feature> |

## 4. Constraints

| Type | Constraint | Source |
|---|---|---|
| Tech | <e.g. runs on Cloudflare Workers> | <wrangler.jsonc> |
| Business | <e.g. zero-cost hosting> | <decision> |
| Regulatory | <e.g. EU data residency> | <client requirement> |
| Time | <e.g. ship by YYYY-MM-DD> | <commitment> |

## 5. User Stories

EARS format: `WHEN <trigger> THE system SHALL <behaviour>`. One row per acceptance criterion so each is independently testable.

### US-001 — <short title>

**As a** <role>, **I want** <capability>, **so that** <benefit>.

| # | Acceptance criterion (EARS) | Verified by |
|---|---|---|
| 1 | WHEN <trigger> THE system SHALL <behaviour> | <test path or demo> |

(Repeat for US-002, US-003, ...)

## 6. Architecture

### Container diagram

```mermaid
graph TB
  user[<User>] --> app[<App>]
  app --> store[(<Data store>)]
  app --> ext[<External service>]
  classDef user fill:#e0af40,stroke:#333,color:#000
  classDef engine fill:#5bbcd6,stroke:#333,color:#000
  classDef output fill:#7dcea0,stroke:#333,color:#000
  class user user
  class app engine
  class store,ext output
```

### Key sequence — <flow name>

```mermaid
sequenceDiagram
  participant U as User
  participant A as App
  participant D as Data
  U->>A: <action>
  A->>D: <query>
  D-->>A: <result>
  A-->>U: <response>
```

### Data model

| Entity | Fields | Notes |
|---|---|---|
| <name> | <fields> | <constraints> |

## 7. Decisions (inline ADRs)

| # | Decision | Chose | Over | Why |
|---|---|---|---|---|
| ADR-001 | <topic> | <X> | <Y, Z> | <one-line reason> |

## 8. Plan

Milestones → stories. Tracer bullet first (thinnest end-to-end slice). Stories map 1:1 to entries here, ordered by build sequence.

| Milestone | Goal | Stories | Status |
|---|---|---|---|
| M1 — Tracer | <thinnest demoable slice> | US-001 | <not started \| in progress \| shipped> |
| M2 — <name> | <goal> | US-002, US-003 | <status> |

## 9. Verification

How we accept each story. Tests, demos, or metrics — pick one per story.

| Story | Method | Location | Status |
|---|---|---|---|
| US-001 | <unit test \| e2e test \| manual demo \| metric> | <path or dashboard> | <pending \| passing \| gap> |

## 10. Open Questions

- [ ] <question> — owner: <who> — by: <when>

## Sources

For from-codebase mode: list every file read during inference.

- `<path>` — used for <section>

For fresh mode: list AskUserQuestion answers as session memory.
````

## Style rules for the spec output

- No em-dashes or en-dashes anywhere. Use commas, colons, full stops, or parentheses.
- No AI-tell vocabulary (delve, leverage, robust, seamless, tapestry, landscape, "in today's fast-paced world", "elevate", "empower", "unlock", "streamline" as filler).
- Tables over bullet lists when the data has 3+ columns of attributes.
- Mermaid diagrams: use the Observatory color theme (amber `#e0af40` for user/sources, cyan `#5bbcd6` for engine, green `#7dcea0` for outputs).
- Mermaid edge labels: spell the trigger, not the jargon. Use `on cache miss`, `on error`, `if signed in`, not `miss`, `err`, `auth`. A reader should understand the edge without knowing the system.
- EARS format only for acceptance criteria. Story description still uses "As a X, I want Y, so that Z".
- Mark every inferred item from from-codebase mode with `(inferred)` so reviewers know to validate.
- One ADR per decision row. Don't pack multiple decisions into one cell.

## Versioning rules

- v1 is the first spec for the project regardless of mode.
- Each subsequent generation increments `<N>`. Never overwrite an existing file.
- The `supersedes` frontmatter field links to the previous version.
- Status starts as `draft`. User updates to `reviewed` after reading, `accepted` after sign-off, `superseded` when a newer version replaces it.

## After writing

1. Print the output path.
2. If `--pdf`, run `/generate pdf <output-path>`. Print the PDF path.
3. If `--vault`, write the summary stub and print its path.
4. Suggest the next step: "Review with the team, then run `/compare-codebase-to-spec` after the next phase to see drift."
