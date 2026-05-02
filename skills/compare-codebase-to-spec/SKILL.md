---
name: compare-codebase-to-spec
description: Audit drift between a spec and the actual codebase. Walks each requirement, ADR, milestone, and verification entry from the spec, checks the code, and emits an audit report with per-item status (✅ implemented, ⚠️ partial, ❌ missing, ➕ extra) plus a drift score. Optional PDF render. Use after each phase, before re-speccing, or when the build feels off-track.
category: development
argument-hint: [--pdf] [--repo <path>] <spec-path>
allowed-tools: Read Write Edit Glob Grep Bash
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Compare Codebase to Spec

Reads a spec produced by `/generate-spec`, walks every checkable item, inspects the codebase, and writes an audit report. The report is the spec, scored against reality.

Sister skills: `/generate-spec` (produces the input spec) and `/compare-specs` (diffs two specs against each other).

## Usage

```
# Spec lives next to the code
/compare-codebase-to-spec docs/specs/spec-v1-fresh-2026-05-02.md

# Spec is a vault-genesis spec, code is in another repo
/compare-codebase-to-spec --repo ~/Dev/myapp vaults/llm-wiki-side-projects/wiki/specs/myapp-spec-v1-fresh-2026-05-02.md

# Explicit repo override
/compare-codebase-to-spec --repo ~/Dev/other-project docs/specs/spec.md

# Render PDF alongside
/compare-codebase-to-spec --pdf docs/specs/spec.md
```

The spec path can be in a repo's `docs/specs/` or in a vault's `wiki/specs/`. Repo resolution order:

1. `--repo <path>` flag if passed.
2. Spec frontmatter `repo` field if non-empty.
3. cwd if it's a git repo.
4. Otherwise abort: ask the user where the code lives.

If `--repo` and the spec's frontmatter `repo` disagree, surface the mismatch but proceed using `--repo`. A vault-genesis spec with empty `repo` frontmatter is the expected case for the first audit after graduation.

## Output

Path: `<repo>/docs/specs/audit-v<N>-YYYY-MM-DD.md` where `v<N>` is the version of the spec being audited. The audit always lives in the repo (next to the code), even when the spec being audited is in a vault. If the spec is vault-genesis, also add a cross-vault link from the vault spec to the new audit.

If `--pdf`, render via `/generate pdf` and print both paths.

## Procedure

### Step 1 — Parse the spec

Read frontmatter (`repo`, `version`, `mode`, `status`). Extract checkable items from each section:

| Section | Item shape | How to verify |
|---|---|---|
| Constitution | principle | grep code/config/docs for adherence; record qualitative finding |
| Outcomes | outcome row | check for evidence (analytics event, metric, deployed surface); often qualitative |
| Scope | "in scope" rows | each must map to at least one shipped story / route / module |
| Constraints | constraint row | check config files (wrangler.jsonc, package.json engines, env vars) |
| User Stories | acceptance criterion (EARS row) | look up "Verified by" path; run if cheap, else read |
| Architecture | container, sequence, data model | match diagrams against actual deps, routes, schema files |
| Decisions (ADRs) | each ADR | check the chosen tech is still in use |
| Plan | milestones, stories | check shipped status against branch/git-log/tag/feature flags |
| Verification | row per story | confirm the named test/demo/metric exists and is green |
| Open Questions | each question | mark resolved if a decision/code answers it |

### Step 2 — Inspect the codebase

For each item, run lightweight checks. Be cheap by default; do not run the full test suite unless the user passes `--run-tests`.

Useful primitives:
- `grep -r` for symbols, env vars, dep names
- Read `package.json`, `wrangler.jsonc`, `drizzle.config.ts`, `tsconfig.json` once and cache
- `git log --oneline | head -50` for recent activity
- `gh pr list --state merged --limit 20` if the user has gh, to check shipped stories
- `find` for routes, components, migrations matching architecture diagram nodes

For acceptance criteria with a "Verified by" test path: read the test file, check it asserts the EARS-claimed behaviour. Do not just check the file exists.

### Step 3 — Classify each item

| Status | Meaning |
|---|---|
| ✅ implemented | Matches spec exactly |
| ⚠️ partial | Implemented but with caveats (subset of behaviour, missing edge case, test gap) |
| ❌ missing | Not implemented |
| ➕ extra | Implemented in code, not in spec |
| 🔄 drifted | Implemented differently (e.g. ADR says X, code uses Y) |
| ❓ unclear | Cannot determine without input from owner |

For ➕ extras: do a structural sweep (routes, deps, exported functions, env vars, migrations) and list anything not referenced by any spec item.

### Step 4 — Drift score

```
drift_score = (partial + missing + drifted + extra) / total_checkable * 100
```

Rounded to integer. Anything ≥ 30 is a signal to re-spec.

### Step 5 — Write the report

````markdown
---
title: Codebase Audit vs Spec v<N>
date: YYYY-MM-DD
spec:
  path: <relative path>
  version: v<N>
  mode: <mode>
  status: <status at audit time>
repo: <repo>
audit-commit: <git rev-parse --short HEAD>
drift-score: <0-100>
---

# Codebase Audit: code vs spec v<N>

> One-sentence summary, e.g. "Audited at commit abc1234 against spec-v1-fresh-2026-05-02. Drift score 18 / 100. 2 stories shipped past spec, 1 ADR reversed."

## Drift score

| Status | Count |
|---|---|
| ✅ implemented | N |
| ⚠️ partial | N |
| ❌ missing | N |
| ➕ extra (in code, not in spec) | N |
| 🔄 drifted (different implementation) | N |
| ❓ unclear | N |
| **Total checkable items** | N |

## Status at a glance

```mermaid
pie title Spec items by status
  "Implemented" : N
  "Partial" : N
  "Missing" : N
  "Drifted" : N
  "Unclear" : N
```

## Section-by-section

### Constitution

| Status | Principle | Evidence | Notes |
|---|---|---|---|
| ✅ | <name> | <file:line or grep result> | |
| ⚠️ | <name> | <evidence> | <caveat> |

### Scope

| Status | Item | Evidence |
|---|---|---|
| ✅ | <feature> | `<path>` |
| ❌ | <feature> | not found |

### User Stories

One row per story; nest acceptance criteria below.

| Status | Story | Title |
|---|---|---|
| ⚠️ | US-003 | <title> |

> US-003 acceptance criteria
>
> | # | Criterion | Status | Evidence |
> |---|---|---|---|
> | 1 | WHEN ... THE system SHALL ... | ✅ | `tests/foo.spec.ts:42` |
> | 2 | WHEN ... THE system SHALL ... | ❌ | not implemented |

### Architecture

For each diagram in the spec: list nodes/edges that match the codebase, ones that drifted, and any structural elements in the code that aren't in the diagram. Embed an updated mermaid diagram if drift is material.

### Decisions (ADRs)

| Status | ADR | Decision | Evidence |
|---|---|---|---|
| ✅ | ADR-001 | Chose Cloudflare Workers | `wrangler.jsonc` |
| 🔄 | ADR-002 | Chose D1, code now uses Neon | `drizzle.config.ts` points at neon-http |

### Plan

| Status | Milestone | Stories | Shipped? |
|---|---|---|---|
| ✅ | M1 | US-001, US-002 | yes (commit `<sha>`) |
| ⚠️ | M2 | US-003 | partial: US-003 shipped, M2 also shipped US-007 not in plan |

### Extras (in code, not in spec)

| Item | Type | Location | Suggest |
|---|---|---|---|
| <feature> | route | `src/routes/admin.tsx` | add to spec or remove from code |
| `POSTHOG_INGEST_HOST` | env var | `wrangler.jsonc` | document in Constraints |

### Open questions

| Question | Status | Resolved by |
|---|---|---|
| <question> | resolved | `<file>` or ADR-00X |
| <question> | still open | |

## Notable findings

Free-form prose, 2-5 bullets. Examples:
- "ADR-002 reversed without an ADR-003. Add the new decision."
- "3 stories ship without a verification path. Add tests or accept as manual."
- "The /admin route has no spec coverage. Either spec it or remove it."

If drift score is low and the codebase tracks the spec well, say so plainly.

## Recommended next actions

| Action | Reason |
|---|---|
| Run `/generate-spec --mode from-codebase` | Produce v<N+1> reflecting current reality |
| Run `/compare-specs v<N> v<N+1>` | Diff old plan vs new reality |
| Resolve N open ADR drifts | Capture new decisions properly |

## Sources

- Spec: `<spec path>`
- Repo: `<repo>` at commit `<sha>`
- Files inspected: <list, max 20, truncate to "+N more">
````

## Style rules for the report

- No em-dashes or en-dashes. Use commas, colons, full stops, or parentheses.
- No AI-tell vocabulary.
- Use status emojis (✅ ⚠️ ❌ ➕ 🔄 ❓) consistently.
- Cite evidence with `path:line` where possible. "Trust me" is not evidence.
- Do not run the full test suite. Read tests, don't execute them, unless `--run-tests` is passed.
- The "Notable findings" section is the only prose; everything else is tables or mermaid.
- If you can't determine status, mark `❓ unclear` and say what input you need. Do not guess.

## Honesty rules

- Do not classify an item as ✅ on the strength of the file existing. Read enough to confirm the EARS behaviour.
- ➕ extras are not failures; they are inputs to the next spec. Frame them neutrally.
- A drift score of 0 is suspicious in any non-trivial project. Sanity-check: did the audit actually walk every section?
- If the spec has open questions still marked open and the code answers them, list each one explicitly. That's where most cheap wins live.

## After writing

1. Print the output path.
2. If `--pdf`, run `/generate pdf <output-path>` and print the PDF path.
3. Suggest the next step based on drift score:
   - Score 0-15: "Spec tracks reality. Optional: refresh `mode: from-codebase` spec."
   - Score 16-30: "Capture extras and drifted ADRs into a v<N+1> spec."
   - Score 31+: "Significant drift. Run `/generate-spec --mode from-codebase` and treat v<N> as superseded."
