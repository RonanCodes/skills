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

## Step 3: Pick the libraries (decision tree)

Walk the content. For each item below, if the answer is yes, include the library's CDN tag in the artefact's `<head>` and use it. Online is always available; size does not matter; the question is whether the library saves real work.

| If the artefact has… | Pull this library | CDN |
|---|---|---|
| Diagrams (flowchart, sequence, mindmap, gantt, timeline, ER, state) | **Mermaid 10** | `cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js` |
| Standard charts (line, bar, pie, radar, scatter, area) | **Chart.js 4** | `cdn.jsdelivr.net/npm/chart.js@4` |
| Genuinely custom data visualisation (force graphs, sankey, treemap, geo, anything Chart.js can't do well) | **D3 7** | `cdn.jsdelivr.net/npm/d3@7` |
| Icons (visual hierarchy, section markers, status indicators) | **Lucide** (font version) | `unpkg.com/lucide-static@latest/font/lucide.css` |
| Interactive primitives (tabs, accordions, alerts, badges, tooltips, copy buttons, dialogs, disclosures, dropdowns) | **Shoelace 2** (web components, accessibility built in) | `cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2/cdn/shoelace-autoloader.js` + the matching theme CSS |
| Light state / toggles (only if Shoelace's reactivity isn't already covering it) | **Alpine.js 3** | `unpkg.com/alpinejs@3` |
| Math / equations | **KaTeX** | `cdn.jsdelivr.net/npm/katex` |
| Code highlighting (when the artefact shows multiple code blocks worth styling) | **highlight.js** (auto-detect) or **Prism** (deliberate theme) | `cdn.jsdelivr.net/npm/highlight.js@11` |
| Sortable / filterable tables (more than ~10 rows, user will want to interact) | **Tabulator** | `cdn.jsdelivr.net/npm/tabulator-tables@6` |
| Animations / scroll effects | **Motion One** (~10KB, modern) or **GSAP** | `cdn.jsdelivr.net/npm/motion@10` |
| Maps | **Leaflet** (light, OSM) or **MapLibre** (vector tiles) | `unpkg.com/leaflet@1.9` |
| 3D / WebGL | **Three.js** | `cdn.jsdelivr.net/npm/three@latest` |

For layout, pick by content shape, not by reflex:

- **Editorial / long-form reading / narrative synthesis** → handcrafted CSS with serif body (Iowan Old Style, Palatino, Georgia stack). The voice lives in the typography; libraries would generic-ify it.
- **Dashboard / report / multi-card comparison** → **Tailwind via Play CDN**, optionally with **DaisyUI** for shadcn-style components. (Note: real shadcn cannot run via CDN; it requires a build step.)

**Default to editorial** unless the content is clearly dashboard-shaped (cards, grids, side-by-side comparisons, KPIs). When in doubt, editorial wins. The user has confirmed editorial typography is the preferred voice.

Avoid by default: jQuery, Bootstrap, full React, MUI, shadcn (build step required).

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
