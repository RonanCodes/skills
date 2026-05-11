---
name: respond-as-html
description: Render the current response (or a specific piece of content under discussion) as a single-file HTML artefact instead of a long Markdown reply. Use whenever the user asks for a "human-readable version", "an artifact", "a shareable page", "an HTML version", "make it pretty", "save that as a page", or similar phrasing. Auto-detects an llm-wiki vault or any repo/folder and writes to `<root>/artifacts/html/<timestamp>-<slug>.html`. Editorial typography baseline with libraries layered in per the decision tree; opens in the user's default browser. Markdown stays the default chat surface; this skill is the explicit promote-to-artefact step.
user-invocable: true
allowed-tools: Bash(mkdir *) Bash(date *) Bash(open *) Bash(git *) Bash(pwd *) Bash(realpath *) Bash(basename *) Bash(test *) Read Write Glob
---

## Philosophy

The artefact will always be opened online. Size does not matter. The question to ask before reaching for any library is: *does it save real work or does it just add weight without changing the outcome?* If it saves real work (diagrams, charts, accessibility-correct components, icons), pull it. Do not optimise for offline-ness or for shaving bytes; optimise for the artefact being good.

The voice lives in the typography and the rhythm. Handcraft those. Libraries handle the visual primitives and the interactive bits where rolling your own would be reinventing wheels.

# Respond as HTML

Snapshot the current response (or a specific piece of content) as a single-file HTML artefact. Markdown stays the chat default. This skill is the explicit "promote this moment to a real artefact" step.

## When to invoke

Fire automatically on intent phrases like:

- "give me a human-readable version"
- "make that an artifact"
- "save that as a page"
- "give me the HTML version"
- "make it pretty"
- "make it shareable"
- "I want to review that properly"
- explicit `/respond-as-html` (or whatever alias the user types)

Do NOT fire for short factual replies, code-only edits, or one-line answers. The smell test: would the user open this in a browser tab and read it side-by-side with something else? If yes, fire. If no, leave it in the terminal.

## What "the current response" means

The content under discussion. In order of preference:

1. The last substantive assistant message in this conversation (a plan, a synthesis, a long analysis, a trend report).
2. A specific message the user points at ("that section above", "the part about X").
3. Content the user pastes inline as the prompt body.

When ambiguous, ask one clarifying question. Don't guess wrong and waste a render.

## Step 1: Resolve the output root

Auto-detect, in this order:

1. **Inside an llm-wiki vault** (cwd or a parent matches `vaults/llm-wiki-*/`). Root = the vault directory. The skill writes to `<vault-root>/artifacts/html/`.
2. **Inside any other git repo.** Root = `git rev-parse --show-toplevel`. Writes to `<repo-root>/artifacts/html/`.
3. **Plain directory, no git.** Root = current working directory. Writes to `<cwd>/artifacts/html/`.

```bash
# Detect root
if pwd | grep -q "/vaults/llm-wiki-"; then
  ROOT="$(pwd | sed -E 's|(.*/vaults/llm-wiki-[^/]+).*|\1|')"
elif git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel)"
else
  ROOT="$(pwd)"
fi
OUT_DIR="$ROOT/artifacts/html"
mkdir -p "$OUT_DIR"
```

Report the chosen root to the user in one short line so they know where the file landed.

## Step 2: Derive title and filename

- **Title**: a short human-readable headline for the artefact. Pull it from the content (first H1, or the most natural summary phrase). Ask the user if nothing obvious.
- **Slug**: kebab-case from the title, max 60 chars.
- **Timestamp**: `YYYY-MM-DD-HHMM` in local time.
- **Filename**: `<timestamp>-<slug>.html`.

```bash
TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
SLUG="<derived-from-title>"
FILE="$OUT_DIR/${TIMESTAMP}-${SLUG}.html"
```

## Step 3a: Pick the style variant by content shape

Four variants. Pick by content shape, not by taste. All four share spacing/radius/shadow tokens; only typography, scale, palette, and layout change.

| Variant | Use when content is… | Heading / Body / Mono | Body size | Layout | Palette light / dark |
|---|---|---|---|---|---|
| **Editorial** (default) | Workshop syntheses, trend scans, AI essays, long-form narrative with diagrams | Newsreader (or Iowan Old Style stack) / Source Serif 4 / JetBrains Mono | 18px, 1.25 scale | Single column, 65ch measure, sticky chapter-only TOC on wide screens, drop cap optional on h1 | Warm paper #FBF7F0 on #1A1714 / #131210 on #E8E2D6 |
| **Reference** | Specs, PRDs, decision trees, API-style docs, glossaries, plans | Inter / Inter / JetBrains Mono | 15px, 1.2 scale | Left sidebar nav + content (max 65-75ch) + optional right TOC; code blocks span full column; both rails sticky | Near-white #FAFAFA on near-black #0A0A0A, single accent from Radix Indigo 9 |
| **Dashboard** | KPI reports, stack research with matrices, comparison documents, dense numeric tables | Geist Sans / Geist Sans / Geist Mono | 14px, tight 1.15 scale, `tabular-nums` on | Multi-column grid (auto-fit minmax 280px), sticky filter/legend bar, summary-detail-source stack | Cool #F7F8FA / #0B0D10, status colours from Radix (green-9 / amber-9 / red-9 / blue-9) plus one brand accent |
| **Journal** | Personal reflections, capture-mode digests, podcast show-notes, book-style pieces | iA Writer Duo (or Newsreader) / iA Writer Quattro (or Source Serif 4) / iA Writer Mono | 19px, loose 1.7 leading, 1.333 scale | Single column, 60ch measure, generous top/bottom whitespace, breadcrumb-only nav, no sidebar | Cream #F5EFE0 on #2A2520 / #1B1814 on #D8CFBF |

Default to **Editorial** unless the content is unambiguously dashboard- or reference-shaped. Editorial is the highest-comprehension layout for narrative and the right default for ~60% of artefacts.

### Typography defaults (all variants)

- **Measure:** 65ch for Editorial and Reference; 60ch for Journal; auto for Dashboard cards. Hard cap at 80ch (WCAG 1.4.8).
- **Line-height:** body 1.55-1.65; headings 1.15-1.25; loose Journal can go 1.7-1.8.
- **Type scale:** modular, set in `rem`. Editorial 1.25 (major third). Reference / Dashboard 1.2 (minor third). Journal 1.333 (perfect fourth).
- **Tabular numerals:** always `font-variant-numeric: tabular-nums` on table cells and KPI numbers.
- **Vertical rhythm:** snap every margin to a 4px or 8px base unit. Heading top-margin ≈ 2× its line-height.
- **Ornaments:** drop caps Editorial-only. Small caps for run-in headings via `font-variant-caps: all-small-caps`. Common ligatures on for serif body, off for code blocks.

### Palette and accent strategy

- **Warm paper** (#FBF7F0 light / #131210 dark) for Editorial and Journal. Avoid pure white #FFFFFF for long-form: contrast ratio 21:1 against black causes glare during long reads.
- **Cool near-white** (#F7F8FA / #FAFAFA) for Dashboard and Reference. Cool greys make charts easier to scan.
- **One accent per artefact** for Editorial and Reference. Three status colours plus one brand accent for Dashboard.
- **Radix Colors** is the recommended palette system (12-step scales with a designed dark parallel). Tailwind palette is fine for prototypes but its dark mode is hue-rotation, which can look muddy. Open Props is the lightest option if just CSS variables are needed.
- **Honour `prefers-color-scheme: dark` by default**, no toggle for read-once artefacts. Dark mode must be a designed pair, not a hue rotation: warm-paper artefacts go to warm near-black, cool dashboards go to cool near-black.

### Standard interactive shell (every variant)

Every multi-chapter artefact gets the same navigation shell so readers move through artefacts with consistent muscle memory:

- **Breadcrumb** at the top with "← Back to index" link.
- **Sticky table of contents** in the left column on screens ≥ 1000px, listing chapters with `01`, `02`, … prefixes, highlighting the active chapter via IntersectionObserver (rootMargin `-30% 0px -55% 0px`).
- **TOC collapses** to a wrap-flex horizontal nav at the top on narrow screens.
- **Each chapter section** has a stable `id="ch-<slug>"` and `scroll-margin-top: 2rem` so anchor jumps don't sit under the breadcrumb.
- **Footer** with source links and back-to-index.

This shell is mandatory for any artefact with 3+ chapters. For 1-2 chapter artefacts, breadcrumb + footer is enough.

### Folder structure when artefacts have child pages

When an artefact is a single self-contained page, write to `artifacts/html/<timestamp>-<slug>.html` (the current default). When an artefact will have child pages (sub-topics, drill-downs), write to a folder instead:

```
artifacts/html/
├── index.html                              # catalog of all artefacts
├── 2026-05-11-1030-pocock-workflow.html    # single-page artefact
└── 2026-05-15-0900-product-spec/           # multi-page artefact
    ├── index.html                          # parent page with its own TOC
    ├── api-reference.html                  # child page 1
    ├── data-model.html                     # child page 2
    └── acceptance-criteria.html            # child page 3
```

The folder makes it trivial to zip and share (`zip -r product-spec.zip 2026-05-15-0900-product-spec/`). All children link back to their parent's `index.html`, and the parent's TOC includes child-page links at the appropriate chapter.

## Step 3b: Pick the libraries (decision tree)

The recommended stack, locked in 2026-05-11 after side-by-side comparison of five styles. Default to this; deviate only with reason.

### Always pulled (these always pay)

| Layer | Library | CDN |
|---|---|---|
| Icons | **Lucide** (font version) | `unpkg.com/lucide-static@latest/font/lucide.css` |
| Diagrams (flowchart, sequence, mindmap, gantt, timeline, ER, state) | **Mermaid 10** | `cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js` |
| Charts (line, bar, area, scatter, dot) | **Observable Plot 0.6** (declarative grammar built on D3, modern API, better defaults than Chart.js) | `cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm` (ES module) |

### Pulled when content demands it

| If the artefact has… | Pull this | CDN |
|---|---|---|
| Genuinely custom data viz (force graphs, sankey, treemap, geo) that Plot can't do well | **D3 7** | `cdn.jsdelivr.net/npm/d3@7` |
| Math / equations | **KaTeX** | `cdn.jsdelivr.net/npm/katex` |
| Code highlighting (3+ code blocks worth styling) | **highlight.js** (auto-detect) or **Prism** | `cdn.jsdelivr.net/npm/highlight.js@11` |
| Sortable / filterable tables (10+ rows, user interaction expected) | **Tabulator** | `cdn.jsdelivr.net/npm/tabulator-tables@6` |
| Animations | **Motion One** (~10KB) | `cdn.jsdelivr.net/npm/motion@10` |
| Maps | **Leaflet** or **MapLibre** | `unpkg.com/leaflet@1.9` |
| 3D / WebGL | **Three.js** | `cdn.jsdelivr.net/npm/three@latest` |

### Interactive primitives: NATIVE HTML5 + ~40 lines custom JS

This is the most important calibration. **Do NOT pull Shoelace, DaisyUI, or any component library by default.** Their design language fights the editorial typography voice and the primitives are small enough to hand-roll.

| Primitive | Recommendation | Notes |
|---|---|---|
| Tabs | Hand-roll with `role="tablist"`, `role="tab"`, `role="tabpanel"` + ~25 lines JS for click, arrow-key nav, focus management | Full keyboard accessibility, voice-coherent |
| Disclosure / accordion | Native `<details>` + `<summary>` | Zero JS |
| Modal / dialog | Native `<dialog>` | Zero JS |
| Tooltips (simple, one-line) | Native `title=""` attribute | Browser handles render and a11y |
| Tooltips / popovers (rich content) | Native `popover` attribute + `popovertarget` | Stable in all evergreen browsers |
| Badges | Styled `<span>` | Zero JS |
| Alerts / callouts | Styled `<div>` with a Lucide icon | Zero JS |
| Copy buttons | `<button>` + ~10 lines JS using `navigator.clipboard.writeText` with class-toggle toast feedback | |

### Modern browser APIs worth using

- **CSS @container queries**, let cards / stat strips respond to their own container width instead of viewport. More robust than media queries.
- **CSS `:has()`**, selectors based on children; sometimes saves JS.
- **`popover` attribute**, covered above; native floating UI.

### Modern browser APIs NOT recommended (gotchas)

- **View Transitions API** for tab switches: causes a visible flash that looks worse than an instant swap. Tested 2026-05-11; do not use for tab content swaps. May be fine for full page navigation.

### Layout system

- **Default: handcrafted editorial CSS** with serif body (Iowan Old Style, Palatino Linotype, Book Antiqua, Palatino, Georgia stack) and sans hierarchy (Inter, system-ui, sans-serif). The voice lives in the typography; libraries would generic-ify it. Use the Observatory palette CSS variables (amber, cyan, green, plum, salmon).
- **Optional: Tailwind via Play CDN** when content is clearly dashboard-shaped (cards, grids, KPI strips, side-by-side comparisons). Optionally with **DaisyUI** for shadcn-style components.

**Default to editorial** unless the content is unambiguously dashboard-shaped. When in doubt, editorial wins. User has confirmed editorial typography is the preferred voice.

### Avoid by default

jQuery (legacy), Bootstrap (heavier than Tailwind for the same payoff), full React (build step kills the single-file premise), MUI (build step), real shadcn (build step), **Shoelace / Web Awesome** (design language fights editorial voice; primitives are 35 lines of JS away), Chart.js as default (use Plot; Chart.js is fine as fallback if Plot doesn't fit).

## Step 3b: Render the HTML

Start from the editorial baseline at `.claude/skills/respond-as-html/template.html`. Layer the libraries you picked in the decision tree above. The baseline gives you:

- Serif body type (Iowan Old Style stack) and sans hierarchy (Inter)
- Light/dark colour scheme respecting `prefers-color-scheme`
- Observatory palette CSS variables (amber, cyan, green, plum accents)
- Header with breadcrumb back to index + eyebrow + title + deck
- Chaptered section structure with section-meta tags
- Editorial pull-quote, stat-strip, figure-with-caption blocks
- Footer with source + back-to-index link

Render the content body as semantic HTML. Convert Markdown to proper HTML, preserve code blocks, tables, lists, blockquotes, images. Never paste raw Markdown inside a `<pre>` block; that defeats the point of promoting to HTML.

If the content has structure cues (multiple H2 sections, lists, tables, sequences, comparisons), use them as visual anchors. Long syntheses get chaptered sections; short reflections get one calm column of prose with a pull quote.

For the Tailwind dashboard variant (when the content is dashboard-shaped), use the Tailwind Play CDN baseline instead. Same content philosophy, different layout primitives.

## Step 4: Write the file

```bash
Write tool with file_path=$FILE and content=<rendered HTML>
```

## Step 4b: Auto-create or update the index

After writing the new artefact, check how many `.html` files (excluding `index.html` itself) live in `$OUT_DIR`:

```bash
COUNT=$(ls "$OUT_DIR"/*.html 2>/dev/null | grep -v "/index.html$" | wc -l | tr -d ' ')
```

- **If COUNT is 1** (just the file you wrote): do nothing. A single artefact does not need an index.
- **If COUNT >= 2**: create or refresh `$OUT_DIR/index.html`. The index:
  - Lists every artefact in the folder, newest first.
  - Title per artefact pulled from `<title>` tag.
  - One-line summary pulled from the artefact's first paragraph or H1 deck (heuristic; fall back to the slug).
  - Stack pill (Tailwind / Plain / etc.) inferred from the artefact's contents.
  - Uses the plain editorial style by default (lightest viable, no CDN dependency).

**Every artefact must include a back-link to the index** in its header *and* its footer:

```html
<nav><a href="index.html">← Back to index</a></nav>
```

The index page itself does NOT need a back-link (it is the root).

The index filename is always literally `index.html`, never timestamped, so its URL stays stable across sessions.

## Step 5: Open in browser

```bash
# If an index exists, open the index. Otherwise open the new artefact.
if [ -f "$OUT_DIR/index.html" ]; then
  open "$OUT_DIR/index.html"
else
  open "$FILE"
fi
```

## Step 6: Report

One short status block to the user:

```
Wrote → artifacts/html/<filename>
Opened in browser.
Root: <root path>
```

That's it. No long summary, no commentary, no "let me know if you'd like changes." The artefact speaks for itself; if the user wants edits they will tell you.

## Style rules for the rendered HTML

- No em-dashes or en-dashes in body text. Convert any present in the source to commas, colons, or full stops per the user's house style.
- No AI-tell vocabulary added by this skill (delve, leverage, robust, seamless, unlock, empower, streamline).
- Preserve the user's voice in any quoted material exactly as-is, even if it contains those words.
- Code blocks: monospace, subtle background. Pull `highlight.js` when the artefact shows multiple code blocks worth styling.
- Tables: full-width, zebra-striped rows, readable on mobile.
- Links: underlined on hover only; never `target="_blank"` by default (let the user choose).
- Light/dark scheme: always respect `prefers-color-scheme`. Both themes must read well.

## Notes

- Single-file output. CDN dependencies are fine; do not try to inline them.
- Online assumption: the artefact will always be opened with network. Do not optimise for offline; optimise for the artefact being good.
- Size does not matter. Do not skip a library because it adds weight. The criterion is whether the library saves real work or just adds weight without changing the outcome.
- Idempotent path: re-running the skill on the same content within a minute produces a different filename (timestamp includes HHMM), so nothing gets clobbered.
- Not committed by default. The user decides what to keep. If the artefact lives inside a vault under git, mention that in the status line; do not auto-`git add`.

## Failure modes to avoid

- **Rendering markdown raw inside `<pre>`**. Always convert to semantic HTML.
- **Writing to a hidden folder**. `artifacts/html/` is intentionally visible. Never use `.artifacts/`.
- **Verbose status messages after the render**. The artefact is the deliverable; the chat reply should be three short lines max.
- **Asking the user for permission to open the browser.** They opted into auto-open during skill design. Just do it.
- **Trying to be a Markdown-to-HTML converter for arbitrary files.** This skill operates on the current conversation context, not on `*.md` files on disk. For converting wiki pages or vaults into HTML mini-sites, use `/generate-portal` or a future `/skill-md-to-html`.
