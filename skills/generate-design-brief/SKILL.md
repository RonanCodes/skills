---
name: generate-design-brief
description: Derive a paste-ready Claude Design brief from an accepted spec. Reads the spec's outcomes, audiences, scope, and UI-surfacing user stories; pulls in any linked branding entity; asks the user for the gaps (vibe references, accent colour, anti-references, tone). Writes the brief into wiki/designs/<project>/brief-v<N>-YYYY-MM-DD.md so it lives as a sibling artefact to the spec and can be re-derived when the spec changes. Use after a spec is accepted and before the design pass starts.
category: development
argument-hint: [--spec <spec-path>] [--vault <vault-short>] [--out <path>] <project-name>
allowed-tools: Read Write Edit Glob Grep Bash AskUserQuestion
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Generate Design Brief

Produces a paste-ready brief for `claude.ai/design` (or Pencil as the second tool) from an accepted spec. The brief is a **sibling artefact** to the spec, not a section inside it: specs stay markdown-diffable; designs and their briefs live next door under `wiki/designs/<project>/`.

Pairs with `/generate-spec` (which produces the input). A future `/spec-mockups` skill would consume this brief to scaffold the actual generation step.

## Usage

```
# Spec-driven (most common)
/generate-design-brief --spec <path-to-spec> <project>

# Look up the spec inside a vault by project name
/generate-design-brief --vault <vault-short> <project>

# Write to a non-default output path
/generate-design-brief --spec <path> --out <path> <project>
```

If `--spec` is omitted, look for the most recent `wiki/specs/<project>-spec-v*.md` in the named vault. If still ambiguous, ask via AskUserQuestion.

## Output

Default path: `vaults/llm-wiki-<vault-short>/wiki/designs/<project>/brief-v<N>-YYYY-MM-DD.md`

Where `<N>` increments by counting existing briefs in that directory. Always create the directory if missing.

The brief's frontmatter records source provenance so the brief can be regenerated later or audited against spec drift:

```yaml
title: <Project> Claude Design Brief
date: YYYY-MM-DD
version: v<N>
source-spec: <relative-path-to-spec>
source-spec-version: v<N>
source-spec-hash: sha256:<hash>
status: draft | reviewed | accepted | superseded
related: [list of vault wikilinks]
```

The `source-spec-hash` lets `lint --artifacts` flag a brief that's gone stale because the underlying spec changed.

## Procedure

### Step 1 — Find and read the spec

- If `--spec <path>` set, read that file directly.
- Else look for `vaults/llm-wiki-<vault-short>/wiki/specs/<project>-spec-v*.md` and pick the highest version. Report which file was chosen.
- Validate spec frontmatter: must have `title`, `version`, and ideally `status: accepted`. If status is `draft`, ask via AskUserQuestion: "Spec status is `draft`. Generate brief anyway?" Default yes (briefs help iterate the spec).
- Refuse if no User Stories section parses (the brief needs UI-surfacing stories).

### Step 2 — Pull in supporting context

For each candidate context source, read if present:

| Source | Used for |
|---|---|
| Spec frontmatter `related: [[branding]]` (or `brand`, `brand-identity`, `design-language`) | Brand identity section: name, vibe, colour, typography rhyme |
| Spec §2 Outcomes | "What it does" + success criteria |
| Spec User Stories with UI surface (US-001..N where the story implies a screen) | "Key screens to design" list |
| Spec §3 Scope `out of scope` rows | "Out of scope for design pass" |
| Spec §4 Constraints rows tagged `Visual` or `Tech (component library)` | "Stack constraints so designs are buildable" |
| Spec §6 Architecture > Visual designs subsection (cross-link to existing briefs) | Avoid duplicating; link instead |

Identify "UI-surfacing user stories": any story whose acceptance criteria mention a route, page, screen, modal, button, or visible state. Heuristic: contains `WHEN ... user ... lands on /` or `WHEN ... user clicks ... THE system SHALL render`. Skip stories that are pure API / backend (e.g. webhook handlers, MCP tools).

### Step 3 — Ask the user for the gaps

These do not live in a spec by default; ask via AskUserQuestion, one or two at a time. Skip a question if the answer is already in a linked branding entity.

1. **Vibe references** — "Name 2-3 products whose look-and-feel you want to echo." (Examples: Linear, Stripe, Notion, Vercel, Calm, Things, Apple Music, Bear.)
2. **Anti-references** — "Name 1-2 products whose look you want to avoid." (Common: Salesforce, generic AI 'purple gradient' marketing pages, enterprise BI tools.)
3. **Accent colour direction** — "One accent colour or hue family. Specific hex if you have it, otherwise 'cool blue' / 'warm amber' / 'forest green'."
4. **Typography lean** — "Editorial serif (think NYT), confident sans (think Inter / Söhne), display geometric (think Mona Sans)? Or 'whatever pairs with the references above'?"
5. **Tone of voice for microcopy** — "Confident technical, calm + minimal, friendly + casual, editorial + writerly?"
6. **Light/dark default** — usually copyable from spec Constraints; only ask if absent.

Optional follow-ups based on project type:
- B2B SaaS: ask about competitor differentiation in one sentence
- Consumer utility: ask about "feel" (delight, calm, no-friction)
- Internal tool: ask about density vs spaciousness preference

### Step 4 — Build the screen list

For each UI-surfacing user story, derive a screen entry:

| Spec source | Brief output |
|---|---|
| Story title | Screen name + short description |
| Story description ("As a X, I want Y so that Z") | One-line user goal |
| EARS acceptance criteria mentioning visible elements | Bullet list of must-have layout/content |
| Out-of-scope rows referencing this screen | "Out of scope for this screen" mini-list |

Group multiple related stories into one screen if they share a route (e.g. US-003 + US-004 both about `/connections` collapse to one Connections screen).

### Step 5 — Write the brief

Use this template. The "## Brief" section starting at the marker is the paste-ready chunk; everything above is metadata for the wiki.

````markdown
---
title: <Project> Claude Design Brief
date-created: YYYY-MM-DD
date-modified: YYYY-MM-DD
date: YYYY-MM-DD
version: v<N>
source-spec: <relative path>
source-spec-version: v<N>
source-spec-hash: sha256:<short>
status: draft
page-type: concept
domain: [<vault default domain>]
tags: [design-brief, <project-name>]
related:
  - "<spec wikilink>"
  - "[[branding]]"
---

# <Project> Claude Design Brief

> Derived from [[<spec-name>]] (v<N>, hash <short>). Paste the section below the marker into `claude.ai/design`. Regenerate via `/generate-design-brief` if the source spec changes; the `source-spec-hash` will flag drift.

Paste-ready brief begins below the divider.

---

## Brief

I'm designing **<Project name>** (<one-line elevator pitch from spec §2 Outcomes top row>).

### What it does

<Two-paragraph description weaving spec §1 Constitution C1 (the core principle) with spec §2 Outcomes (user-visible payoff). Real and concrete; no marketing fluff.>

### Who it's for

<For each distinct "As a <role>" in spec User Stories, group into 1-3 audience profiles. Per profile: one paragraph covering current behaviour (what they do today without this product) + tone fit.>

### Brand identity

- Name: **<Name>** (capitalisation rule from branding entity, e.g. "all caps")
- <Visual rhyme / typographic rule if present in branding>
- Vibe: <user's vibe references string, plus a one-line "closer to X than to Y" framing>
- One accent colour, generous whitespace, real data on screen (not Lorem Ipsum), confident but small typography.

### Key screens to design

Please produce these as separate artifacts. For each, prioritise readable real data over decorative elements.

<For each derived screen: numbered heading, route, must-haves bullet list, mini "out of scope" if any.>

### Out of scope for this design pass

<Bullet list from spec §3 Scope out-of-scope rows that touch UI, plus any "designed in next pass" items the user named in step 3.>

### Stack constraints (so designs are buildable)

- <From spec §4 Constraints visual rows: framework (e.g. React + TanStack Start), component library (shadcn/ui + Tailwind v4), light/dark default, target form factors.>

### Tone of voice

<From step 3 user answer: tone direction in 1-2 sentences. E.g. "Confident, calm, no jargon. Think 'your sharp friend who happens to know your store inside out', not 'enterprise BI tool'.">

### Deliverables

A clickable prototype across the screens above, with a consistent type ramp, colour system, and one accent. Please share the artifact link once ready.

---

## After the design pass

When variants come back from Claude Design (or Pencil as the second tool):

1. Save each variant into `<vault>/wiki/designs/<project>/mockups/` as `<screen>-variant-<N>.<ext>`.
2. Write a sidecar `<screen>-variant-<N>.<ext>.meta.yaml` recording: source spec, source spec hash, brief path, brief hash, prompt used, status (`candidate` / `chosen` / `rejected`).
3. Mark chosen variants in their sidecar and link them from the spec's User Stories (US-001 → "design: see [[<chosen mockup>]]").
4. The (future) `/spec-mockups` skill automates steps 1-3.

## Design tools used (and which job each one does)

The two jobs are different and want different tools.

**UI mockups (the screens above):**

- **Claude Design** at `claude.ai/design` — primary surface. Whole-screen layouts, real data, interaction states.
- **Pencil** — second-opinion / divergent layouts when one Claude artifact is not landing. Bring the better one back into Claude Design for refinement. Avoid v0 (per project canon).
- Image generators (Gemini, DALL-E) are wrong for screen design even when the rendered visuals look polished. They produce unclickable PNGs.

**Marketing imagery (hero illustrations, OG cards, social):**

- **Nano Banana 2** via `/ro:generate-image` — the canonical image generator for marketing assets.
- For the marketing landing page hero: use `/ro:generate-image` with prompts derived from the brand identity section above.
````

### Step 6 — Compute and write source-spec-hash

After writing the file, compute `sha256` over the source spec content (header + body) and patch it into the brief's frontmatter. This is the value `lint --artifacts` will check on later runs.

```bash
shasum -a 256 <spec-path> | cut -c1-16   # short hash for readability
```

### Step 7 — Open the brief

Open the new brief in Obsidian via the obsidian:// URL form so the user can review immediately.

### Step 8 — Print summary

```
✅ Design brief generated.
   spec: <spec path>
   brief: <brief path>
   screens: N derived from N user stories
   gaps filled: <list of step-3 questions answered>

Next: paste the section below "## Brief" into claude.ai/design.
      Save variants into <vault>/wiki/designs/<project>/mockups/ with sidecars.
```

## Style rules for the brief

- No em-dashes or en-dashes. Use commas, colons, full stops, parentheses.
- No AI-tell vocabulary (delve, leverage, robust, seamless, tapestry, landscape, "elevate", "empower", "unlock", "streamline" as filler).
- No rhetorical reversals ("not just X but Y").
- Real concrete language. If the spec says "sign-up via Clerk with Google OAuth", the brief says "sign-up screen using the Clerk hosted component, email + Google providers", not "a sleek authentication experience".
- Tables only when comparing options. Bullet lists for must-haves. Prose for tone and brand.
- No mockups embedded in the brief. The brief is text. Designs are sibling artefacts.

## Honesty rules

- If the spec has only API / backend stories (no UI surface), say so and refuse to generate a brief. Don't invent screens.
- If the user has no preference on a Step 3 question, mark it "to be decided in the design review" rather than fabricating a vibe.
- If the linked branding entity contradicts user answers from Step 3, surface the conflict and ask the user to reconcile, then update either the branding entity or the brief (not silently both).

## What this skill does NOT do

- It does not generate the actual mockups. That's `claude.ai/design` (or Pencil) with a human in the loop.
- It does not predict accent colours or typography unilaterally. Those come from the user.
- It does not maintain ongoing sync with the spec. Re-run the skill after spec changes; `lint --artifacts` flags drift.
- It does not write a separate "marketing imagery" brief. Hero illustrations and OG cards are out of scope for the design tool; use `/ro:generate-image` for those.
