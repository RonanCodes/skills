---
name: visual-diff
description: Compare images for visual correctness using pixel diff and Claude vision. Use for screenshot comparison, visual regressions, design-match checks (current UI vs a reference image), or per-component diffs against a design.
category: browser-visual
argument-hint: <image1|url> <image2> [--threshold 95] [--baseline] [--reference <path|url>] [--selector <css>] [--reference-page <url>] [--reference-selector <css>]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:primitive
---

# Visual Diff

Compare two images using pixel-level diffing and Claude's multimodal vision. Two workflows:

- **Regression** — current vs saved baseline ("did my edit break anything?")
- **Design-match** — current vs a reference image or live design ("does my UI match this NYT screenshot?")

## Usage

```
# Regression (as before)
/visual-diff screenshot.png baseline.png
/visual-diff current.png --baseline                       # save as baseline

# Design-match — whole page vs a local reference
/visual-diff http://localhost:3000 --reference ./design.png

# Design-match — whole page vs an online reference (curl-fetched)
/visual-diff http://localhost:3000 --reference https://example.com/nyt-connections.png

# Per-component — crop the live page by CSS selector
/visual-diff http://localhost:3000 --selector '[data-slot="card"]' --reference ./card-ref.png

# Per-component — reference is a live page too (both sides selected)
/visual-diff http://localhost:3000 --selector '.word-tile' \
  --reference-page https://www.nytimes.com/games/connections --reference-selector '[data-testid="card"]'
```

## Comparison

### 1. Quantitative — Pixel Diff

If ImageMagick is available (`which compare`):
```bash
compare -metric AE image1.png image2.png diff.png 2>&1
# total_pixels=$(identify -format "%w*%h" image1.png | bc)
# match = (1 - differing/total) * 100
```
Or `npx pixelmatch image1.png image2.png diff.png --threshold 0.1`. Skip if neither tool is available.

**Size normalisation** — if the two images differ in dimensions (common for design-match where the reference was captured at a different scale), resize the smaller to the larger's box before pixel-diffing:
```bash
identify -format "%wx%h" image1.png    # e.g. 1440x900
identify -format "%wx%h" image2.png    # e.g. 1024x640
convert image2.png -resize 1440x900\! image2-scaled.png
compare -metric AE image1.png image2-scaled.png diff.png
```

Report both the raw metric and the scaled result. Design-match is noisier by nature — set threshold lower (e.g. 85%) and lean harder on Claude vision for the verdict.

### 2. Qualitative — Claude Vision

Read both images with the Read tool (Claude is multimodal) and analyze:
- Compare layout, colors, typography, spacing, alignment, border radius, shadow depth
- Flag real issues: wrong colors, missing elements, broken layout, font-family mismatch
- Ignore noise: subpixel rendering, antialiasing, font hinting, different OS render stacks

This is the key insight — Claude sees both images and reasons about visual correctness better than pixel diff alone. For design-match against Figma exports or online screenshots, pixel diff often scores ~60% even when the match is "right enough"; Claude vision is the decisive check.

## Modes

- **Default (2 positional args)** — compare image1 to image2 directly.
- **`--baseline`** — save image1 to `.visual-diff/baselines/` as the new baseline, exit.
- **`--threshold N`** — pass/fail percentage for pixel diff (default: 95% for regression, 85% for design-match).

### Design-match flags

If the first argument looks like a URL (starts with `http://` or `https://`), the skill launches playwright to capture the current state:

1. **Current-side capture** — navigate to the URL, screenshot the page (or `--selector` crop if passed). Save to `.visual-diff/tmp/current-<name>.png`. Wait for `networkidle` before capturing.
2. **Reference acquisition** — one of:
   - `--reference <local-path>` — read from disk.
   - `--reference <http-url>` — `curl -sSL -o .visual-diff/tmp/ref.png <url>` (add User-Agent header to avoid 403s).
   - `--reference-page <url> --reference-selector <css>` — playwright opens the reference URL and screenshots, optionally cropped.
3. **Compare** — run pixel diff (size-normalised) + Claude vision on the two images.

### Per-component (`--selector`)

When cropping by CSS selector:
- Playwright: `page.locator(selector).first.screenshot({ path, omitBackground: true })`. `omitBackground` helps when the component is translucent.
- Wait for the element to be visible (`waitFor({ state: 'visible' })`) before screenshotting.
- If the selector matches nothing, fail fast with the selector echoed back.
- If `--reference-selector` is also passed, crop the reference side symmetrically so like-for-like.
- Common useful selectors: `[data-slot="card"]`, `button[data-variant="default"]`, `[role="dialog"]`, `header`, `nav`.

### Reference-URL fetching

When `--reference` is an HTTP URL:
```bash
mkdir -p .visual-diff/tmp
curl -sSL -A "Mozilla/5.0 (compatible; visual-diff)" -o .visual-diff/tmp/ref.png "$URL"
# Verify it's actually an image — URLs behind auth often return HTML instead
file .visual-diff/tmp/ref.png | grep -qE 'image|PNG|JPEG|GIF|WebP' || {
  echo "Reference URL did not return an image (probably an auth/HTML page)"; exit 1;
}
```

Do **not** fetch from URLs that require auth (paywalled NYT, etc.) — you'll get an HTML error page. For those, the user should either:
- Save the image manually and pass `--reference <local-path>`, or
- Use `--reference-page <url>` with a playwright flow that handles login.

## Storage

```
.visual-diff/
├── baselines/      # regression baselines (can be committed if you want a tracked reference set)
├── references/     # design-match reference images (rarely committed; gitignore by default)
├── diffs/          # produced diff images (always ignored)
└── tmp/            # fetched/captured intermediates (always ignored)
```

Add `.visual-diff/tmp/`, `.visual-diff/diffs/`, and typically `.visual-diff/references/` to `.gitignore`.

## Output

```markdown
## Visual Diff Report
- Mode: design-match (component)
- Current: http://localhost:3000 → selector `.word-tile` (captured 2026-04-23)
- Reference: ./nyt-tile-reference.png (1024x1024 → scaled to 1440x1440)
- Pixel match: 81.3% (threshold: 85%) — below
- Claude vision verdict: Close match. Background correct (#efefe6). Letter-spacing looks ~0.01em tighter in current; tile radius is 8px in both. One real issue: font-weight is 600 in current vs 700 in reference.
- Diff image: .visual-diff/diffs/word-tile-diff.png
- Status: Fail — font-weight mismatch
```

Always report Claude's verdict *and* the pixel metric. The verdict is the decision; the metric is evidence.

## Rules

1. Claude vision is always the tiebreaker — pixel diff is supplementary.
2. Pixel diff is supplementary — skip gracefully if `compare`/`pixelmatch` are missing.
3. Distinguish real issues from rendering noise in the report (subpixel, antialiasing, cursor blink, loading spinners).
4. Size-normalise before pixel diff when images differ in dimensions — otherwise the metric is meaningless.
5. Use descriptive filenames in `.visual-diff/tmp/` that include the selector or reference source, not just `current.png`, so parallel runs don't clobber.
6. For design-match: lower the threshold (85% default), lean on Claude vision.
7. Never commit large reference screenshots unless the user explicitly asks — store in `.visual-diff/references/` and gitignore.
8. If a selector matches multiple elements, take the first and say so in the output — don't silently average or loop.
