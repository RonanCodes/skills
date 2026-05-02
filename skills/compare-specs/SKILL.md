---
name: compare-specs
description: Diff two specs produced by /generate-spec. Walks the 10-section template, builds a section-by-section change table, a mermaid sankey of additions/removals/changes, and a drift score. Optional PDF render. Use to compare initial vs post-phase-1 spec, or two competing drafts before commit.
category: development
argument-hint: [--pdf] <spec-a-path> <spec-b-path>
allowed-tools: Read Write Edit Glob Grep Bash
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Compare Specs

Reads two spec files, walks the 10 sections of the spec template, and emits a single comparison report. Common pairings:

- `spec-v1-*.md` vs `spec-v2-*.md` in the same `docs/specs/` directory (drift between phases of the same project).
- A vault-genesis spec (`vaults/.../wiki/specs/<name>-spec-v1-fresh-*.md`) vs the corresponding from-codebase spec in the repo (`<repo>/docs/specs/spec-v2-from-codebase-*.md`). This is the headline "what we said vs what we built" diff.
- Two competing drafts of v1 before either is accepted.

Sister skills: `/generate-spec` (produces the inputs) and `/compare-codebase-to-spec` (audits drift between spec and code).

## Usage

```
/compare-specs docs/specs/spec-v1-fresh-2026-05-02.md docs/specs/spec-v2-from-codebase-2026-08-15.md
/compare-specs --pdf <a> <b>
```

Both arguments are paths. By convention A is older / planned, B is newer / actual, but the report works either way.

## Output

Versions are read from each spec's frontmatter.

Path rules:
- If both specs live in the same `docs/specs/` directory: write the report next to them as `<repo>/docs/specs/diff-v<A>-vs-v<B>-YYYY-MM-DD.md`.
- If one spec is in a vault and the other is in a repo (lifecycle comparison): write to the repo's `docs/specs/diff-vault-genesis-vs-v<B>-YYYY-MM-DD.md` and add a cross-vault link from the vault spec.
- If both specs live in vault `wiki/specs/` directories: write to the same vault as `wiki/specs/diff-<A>-vs-<B>-YYYY-MM-DD.md`.
- If the two specs cover different non-empty `repo` fields, abort: comparing across projects is meaningless.

If `--pdf`, render via `/generate pdf` and print both paths.

## Procedure

### Step 1 — Validate inputs

Read frontmatter of both files. Confirm:
- Both have `title`, `version`, `mode` fields. `repo` may be empty on a vault-genesis spec; that is valid.
- If both have a non-empty `repo`, they must match. If they disagree, stop and surface the mismatch.
- If only one has `repo` populated, that is the lifecycle case (genesis vault spec vs post-graduation repo spec). This is a meaningful comparison: it shows what we said we'd build vs what we built. Annotate the report header with this.
- A and B are not the same file.

### Step 2 — Section walk

For each of the 10 template sections, extract the content from both specs. For sections that contain tables (Outcomes, Scope, Constraints, User Stories, Decisions, Plan, Verification), parse the rows and compare by stable key:

| Section | Stable key |
|---|---|
| Constitution | principle name (bold-prefixed) |
| Outcomes | outcome text |
| Scope | row (in/out preserved) |
| Constraints | type + constraint |
| User Stories | story ID (US-NNN) |
| Architecture | diagram name |
| Decisions | ADR ID |
| Plan | milestone ID |
| Verification | story ID |
| Open Questions | question text |

Classify each row as:
- **added** (in B, not in A)
- **removed** (in A, not in B)
- **changed** (key matches, content differs)
- **unchanged** (key matches, content identical)

For prose sections, do a structural diff: list new headings, removed headings, materially changed paragraphs.

### Step 3 — Report

Write the report using this template:

````markdown
---
title: Spec Comparison <A> vs <B>
date: YYYY-MM-DD
spec-a:
  path: <relative path>
  version: v<A>
  mode: <mode>
  date: <date>
spec-b:
  path: <relative path>
  version: v<B>
  mode: <mode>
  date: <date>
repo: <shared repo>
drift-score: <0-100>
---

# Spec Comparison: v<A> vs v<B>

> One-sentence summary: e.g. "v1 was the up-front plan, v2 is the from-codebase reflection 4 months later. Drift score 32 / 100."

## Drift score

Calculated as `(added + removed + changed) / total * 100`, rounded.

| Bucket | Count |
|---|---|
| Added (in B only) | N |
| Removed (in A only) | N |
| Changed (key matches, content differs) | N |
| Unchanged | N |
| **Total tracked items** | N |

## Change overview

```mermaid
sankey-beta

v<A> spec, Unchanged, N
v<A> spec, Removed, N
v<A> spec, Changed, N
v<B> spec, Unchanged, N
v<B> spec, Added, N
v<B> spec, Changed, N
```

## Section-by-section

### Constitution

| Status | Principle | v<A> | v<B> |
|---|---|---|---|
| ➕ added | <name> |  | <text> |
| ➖ removed | <name> | <text> |  |
| 🔄 changed | <name> | <old text> | <new text> |
| ✅ unchanged | <name> | <text> | <text> |

(Repeat the table format for each section. Omit unchanged rows when the section has more than 5 unchanged items — replace with a single "✅ N items unchanged" line to keep the report readable.)

### User Stories

Extra column: did the acceptance criteria change?

| Status | ID | Title | Criteria changes |
|---|---|---|---|
| 🔄 changed | US-003 | <title> | +2 / -1 / 4 unchanged |

### Architecture

Diagram-by-diagram. If the mermaid source changed, embed both side-by-side and call out the structural delta in prose underneath.

### Decisions (ADRs)

If an ADR was reversed or replaced, mark with `↩️ reversed`. Cross-link the new decision.

## Notable themes

Free-form prose section. Pick out 2-5 themes the diff reveals. Examples:
- "Scope grew: 4 new stories, 0 removed."
- "ADR-002 was reversed: we tried X, fell back to Y."
- "Verification gaps closed: 3 stories went from manual demo to automated test."

Keep this honest. If drift is low and boring, say so.

## Recommended next actions

| Action | Why |
|---|---|
| Update spec-a status to `superseded` | Now that v<B> exists |
| Run `/compare-codebase-to-spec` against v<B> | To check current code matches |

## Sources

- `<path-a>` — spec A
- `<path-b>` — spec B
````

## Style rules for the report

- No em-dashes or en-dashes. Use commas, colons, full stops, or parentheses.
- No AI-tell vocabulary.
- Use status emojis (➕ ➖ 🔄 ✅ ↩️) consistently across all section tables.
- The drift score is one integer, no precision theatre.
- The "Notable themes" section is the only prose; everything else is tables or mermaid.
- If the drift is zero (specs are identical), still produce the report but make it short: "No tracked changes between v<A> and v<B>." with the empty buckets table.

## After writing

1. Print the output path.
2. If `--pdf`, run `/generate pdf <output-path>` and print the PDF path.
3. Suggest the next step: "Review with the team. If v<B> reflects current intent, mark v<A> as `superseded` in its frontmatter."
