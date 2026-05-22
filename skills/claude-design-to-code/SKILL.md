---
name: claude-design-to-code
description: Turn a Claude Design (claude.ai/design, Anthropic Labs) handoff into production code in an existing repo. Walks an agent through getting the source bundle, mapping its design tokens to CSS variables, exposing the design system on an admin-gated /styleguide route, building token-driven components, fixing exported asset alpha channels, slicing each screen into swarm-friendly issues pinned to the committed prototype, and auditing fidelity before declaring done. Use when the user says "implement this Claude design", "claude design to code", "build this design file/zip", "build this design handoff", or hands over an api.anthropic.com/v1/design/h/<id> link or a handoff .zip. Downstream pair of generate-claude-design-prompt (that one writes the brief; this one implements the result).
allowed-tools: Bash Read Glob Grep Write Edit WebFetch
category: browser-visual
---

# Claude Design to Code

Implement a **Claude Design** handoff as production code inside a real repo. The sibling skill `generate-claude-design-prompt` writes the brief and a human runs Claude Design; this skill picks up the resulting handoff (a link or a `.zip`) and turns it into shipped, on-brand, token-driven UI.

Claude Design is Anthropic Labs' AI-native design tool. Its handoff bundle is **not a PNG or a Figma URL**: it ships the component structure as a machine-readable spec, the design tokens actually used on the canvas, the layout hierarchy, the referenced assets, and the design intent. Because it comes from the same model family as Claude Code, you do not have to infer intent from pixels. You still have to land it faithfully in the repo's existing system, and that is where the work is.

## When to use

- A human ran Claude Design and handed you a share link (`api.anthropic.com/v1/design/h/<id>`) and/or a handoff `.zip`.
- A `blocked-on-human` design-input issue (from `generate-claude-design-prompt`) just had its design posted back.
- The user says "implement this design", "build this handoff", "make the app match the mockup".

## When NOT to use

- No design exists yet. Run `generate-claude-design-prompt` first to write the brief, then have a human run Claude Design.
- Greenfield aesthetic exploration with no source bundle. That is `frontend-design`.
- The repo has no design system at all and you just want to scaffold one. Run `design-system-create` first, then come back here to reconcile the handoff tokens against it.

## Workflow

### 1. Get the source, then commit it into the repo

You will be given a link, a `.zip`, or both. **Prefer the zip.** Hard-won gotchas:

- **The share link is time-limited.** It expires within hours and returns 404 to `curl` / `WebFetch` after that. Workers that re-fetch a dead link mid-run get nothing.
- **`WebFetch` chokes on the bundle.** It is a ~14MB gzipped tar, too big for WebFetch to parse.
- **The zip does not expire.** It is the reliable backup.

So:

```bash
# If given a zip: extract it
unzip handoff.zip -d /tmp/design-bundle

# If given ONLY a link: fetch it EARLY with curl, not WebFetch
curl -fsSL "https://api.anthropic.com/v1/design/h/<id>" -o /tmp/bundle.tgz
gunzip -c /tmp/bundle.tgz | tar -xf - -C /tmp/design-bundle
```

Then **commit the extracted bundle into the repo** (e.g. `docs/design/`) as the durable source of truth, so no worker ever re-fetches a dead link:

```bash
mkdir -p docs/design && cp -R /tmp/design-bundle/* docs/design/
git add docs/design && git commit -m "📝 docs(design): commit Claude Design handoff bundle"
```

Uploading a zip to a GitHub issue is awkward and slices can't reliably read it. Committing the extracted prototypes and referencing `docs/design/<screen>.jsx` from each slice is the pattern that works.

### 2. Read the bundle in dependency order, and respect its OWN scoping

Read the **README first**. Then open the entry HTML file (e.g. `Lekkertaal.html`) and follow its imports: `ui.jsx`, `styles.css`, `screens-*.jsx`. Build a map of which prototype file backs which screen.

Respect the design's own scoping. Variants are often marked **out-of-scope** or **explore** (e.g. "SCREEN 1b, explore variant"). Read the chat transcript if it shipped with the bundle for "chosen vs deprecated" decisions, and **do not implement declined variants even when asked to build "everything"**. (Real lesson: a canal-scene explore variant got built, then reverted.) When in doubt about whether a variant is chosen, ask before building it.

### 3. Map design tokens to global CSS variables

The bundle ships a `styles.css`. Reconcile its tokens with the app's. **Map every colour, spacing, radius, and font token to a CSS variable. Do not hardcode hex/px values into components.**

For **Tailwind v4**, use the CSS-first `@theme` block (no `tailwind.config.js`). Tailwind v4 exposes all theme tokens as CSS variables by default:

```css
/* src/styles/globals.css */
@import "tailwindcss";

:root {
  /* semantic tokens from the handoff's styles.css */
  --canal-blue: #2b6cb0;
  --tulip: #e0407f;
  --radius-card: 1rem;
}

@theme {
  --color-canal-blue: var(--canal-blue);
  --color-tulip: var(--tulip);
  --radius-card: var(--radius-card);
  --font-display: "<the handoff's display font>", sans-serif;
}
```

If the project uses shadcn/ui, keep `tailwind.cssVariables: true` in `components.json` (the default) so `bg-background` resolves through the semantic layer. Define global tokens in `@theme`; component-specific tokens can scope to the component file but should still reference the semantic vars, never raw values.

### 4. Map to Tailwind utilities, not magic values

Once tokens are variables, components use `bg-canal-blue rounded-card font-display`, not `bg-[#2b6cb0]`. If you see a magic value in a component, it is a missing token. Add the token, then reference it.

### 5. Expose the design system on an admin-gated `/styleguide` route (all environments)

Create or extend the design system, and surface it on a `/styleguide` route that is **available in all environments** (not dev-only), role-gated so admins can always review the live system. Include the **mascot/asset cast, tokens, palettes, and components**. This is the cheapest way to keep fidelity honest as parallel slices land.

If the route doesn't exist, `design-system-create --showcase-only` adds it in one pass without overwrite risk. In a Clerk app, gate it to `superadmin + staff` via `requireRole()`.

### 6. Build components with the project's component system

If `components.json` exists, build with **shadcn/ui** and extend its primitives. If it doesn't, the app likely rolls **custom token-driven components** instead. **Detect first; adapt, don't force.** Do not refactor a non-shadcn app onto shadcn just because the handoff looks shadcn-shaped. Match the repo's existing pattern.

```bash
test -f components.json && echo "shadcn: extend its primitives" || echo "custom components: match the existing pattern"
```

### 7. Use the project's icon set, not emoji glyphs

Find the installed icon library (usually **Lucide** in this stack) and use it. The handoff may use emoji as placeholders; replace them with real icons from the project's set.

```bash
grep -l "lucide-react\|@lucide\|react-icons" package.json
```

### 8. Check every image and asset renders well (alpha-channel gotcha)

**Recurring bug:** exported mascot / illustration PNGs often have **white backgrounds and no alpha channel**, so they render as white boxes on coloured surfaces. Fix with an ImageMagick corner flood-fill that removes the outer white but **preserves interior whites** (eyes, teeth, highlights):

```bash
magick in.png -alpha set -bordercolor white -border 1 -fuzz 12% \
  -fill none \
  -draw "alpha 0,0 floodfill" \
  -draw "alpha %[fx:w-1],0 floodfill" \
  -draw "alpha 0,%[fx:h-1] floodfill" \
  -draw "alpha %[fx:w-1],%[fx:h-1] floodfill" \
  -shave 1x1 out.png
```

Flood-fill from all four corners, then `-shave 1x1` to drop the border you added. **Verify visually** afterward (open the file or render the styleguide), don't trust the command ran clean.

### 9. Slice and build

Map each design **screen** to its real route/component. Slice into **one-file-per-slice** issues so a swarm can build them in parallel. For each slice:

- Pin it to its source: reference `docs/design/<screen>.jsx` in the issue body (committed in step 1, so the link never dies).
- Carry the chosen palette / tokens forward; never re-pick colours per slice.
- Keep slices file-disjoint where possible so parallel workers don't collide.

Hand the sliced issues to `/ro:planner-worker` (alias `/ro:swarm`) or `/ro:night-shift` for the parallel build. Use `slice-into-issues` to generate them from a parent.

### 10. Audit fidelity before declaring done

The first pass often builds from a written spec and **misses layout motifs that only exist in the prototype**. After building, run a fidelity audit:

- **Grep the design's class names / motifs in `src/`** to confirm they landed:
  ```bash
  # pull distinctive class names from the prototype, check they exist in src
  grep -ohE 'className="[^"]+"' docs/design/*.jsx | tr ' ' '\n' | sort -u > /tmp/design-classes
  ```
- **Classify each screen MATCH / PARTIAL / MISSING** against its prototype. Anything PARTIAL or MISSING becomes a follow-up slice.
- Visual-diff is the stronger check: `close-the-loop` compares the built route against a screenshot of the prototype.

Do not declare done on the strength of "I built the components". Declare done when the audit says MATCH.

## Cross-cutting gotchas (from a live run)

- **`styles.css` is the parallel-collision point.** When many workers each append a token block to one `styles.css`, the file tail is where they conflict. Resolve **additively**: reset your copy to `main`, re-append only your block, never accept a merge that drops another worker's block.
- **Verify you're on the merged code before auditing or deploying.** A stale local checkout once nearly shipped pre-redesign code. `git fetch && git log --oneline -5 origin/main` and confirm the redesign PRs are in your working tree before you audit or ship.
- **Audit beats trust.** The most common failure is building from the written brief and skipping the prototype's actual layout. Step 10 is not optional.

## Relationship to other skills

- **`generate-claude-design-prompt`**: the upstream pair. That skill writes the Claude Design brief and the human-checkpoint issue; this skill implements what comes back. They are two halves of one loop: brief, human runs Claude Design, handoff, this skill builds it.
- **`frontend-design`**: greenfield aesthetic direction with no source bundle; also owns the `/styleguide`-first rule this skill reuses.
- **`design-system-create`**: scaffolds the design system + `/styleguide` route this skill reconciles tokens into. Run it first if the repo has none.
- **`design-system-audit`**: deeper enforcement of the token/spacing/type invariants after the build.
- **`app-polish`**: post-ship launch polish; run after the design lands and is auditing MATCH.
- **`planner-worker` / `swarm` / `night-shift`**: the parallel build engines for the sliced screen issues from step 9.
- **`close-the-loop`**: the reviewer side: visual-diff each built route against the prototype screenshot.

## Sources

- Anthropic: [Introducing Claude Design](https://www.anthropic.com/news/claude-design-anthropic-labs)
- [Claude Design to Claude Code: AI Design Handoff](https://claudefa.st/blog/guide/mechanics/claude-design-handoff): what the handoff bundle contains (machine-readable component spec + tokens + layout + assets + intent), export flow, and research-preview limitations (inline comments occasionally vanish, large monorepos lag when linked).
- [Using Claude Design for prototypes and UX](https://claude.com/resources/tutorials/using-claude-design-for-prototypes-and-ux)
- [From Prompt to Production: a designer's step-by-step workflow with Claude Design + Claude Code](https://www.designsystemscollective.com/from-prompt-to-production-a-designers-step-by-step-workflow-with-claude-design-claude-code-a7705daad026)
- [Theming - shadcn/ui](https://ui.shadcn.com/docs/theming) and [Tailwind v4 - shadcn/ui](https://ui.shadcn.com/docs/tailwind-v4): the `cssVariables` + `@theme` token workflow.
- [Theme variables - Tailwind CSS](https://tailwindcss.com/docs/theme): Tailwind v4 exposes all theme tokens as CSS variables; CSS-first `@theme` replaces `tailwind.config.js`.
- Live-run lessons (Lekkertaal redesign): captured in `.ralph/patterns.md` of the implementing repo.
