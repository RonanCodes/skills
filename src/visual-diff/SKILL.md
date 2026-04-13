---
name: visual-diff
description: Compare two images for visual correctness using pixel diff and Claude vision. Use when comparing screenshots, checking visual regressions, diffing against designs, or verifying UI matches a baseline.
argument-hint: <image1> <image2> [--threshold 95] [--baseline]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Visual Diff

Compare two images using pixel-level diffing and Claude's multimodal vision for accurate visual verification.

## Usage

```
/visual-diff screenshot.png baseline.png
/visual-diff current.png design-spec.png --threshold 90
/visual-diff screenshot.png --baseline
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

### 2. Qualitative — Claude Vision

Read both images with the Read tool (Claude is multimodal) and analyze:
- Compare layout, colors, typography, spacing, alignment
- Flag real issues: wrong colors, missing elements, broken layout
- Ignore noise: subpixel rendering, antialiasing, font hinting differences

This is the key insight — Claude sees both images and reasons about visual correctness better than pixel diff alone.

## Modes

- **Default** — run both quantitative and qualitative, report results
- **`--baseline`** — save image1 to `.visual-diff/baselines/` as the new baseline
- **`--threshold N`** — pass/fail percentage for pixel diff (default: 95%)

## Storage

Save baselines to `.visual-diff/baselines/`, diffs to `.visual-diff/diffs/`. Add `.visual-diff/` to `.gitignore`.

## Output

```markdown
## Visual Diff Report
- Pixel match: 97.8% (threshold: 95%)
- Status: Pass
- Differences: Button color shifted (#3B82F6 vs #2563EB), no other issues
- Diff image: .visual-diff/diffs/home-desktop-diff.png
```

## Rules

1. Always use Claude vision — it catches semantic issues pixel diff misses
2. Pixel diff is supplementary — skip gracefully if tools are missing
3. Distinguish real issues from rendering noise in the report
4. Use descriptive baseline names that include page and viewport
