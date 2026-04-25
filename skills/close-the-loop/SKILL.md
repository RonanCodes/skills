---
name: close-the-loop
description: Automated verification loop that ensures work is done — tests pass, UI works, screenshots match designs. Use when you want to verify stories, check everything works, close the loop, run acceptance checks, or match a UI to a reference design component-by-component.
category: development
argument-hint: [--all | --story <id> | --url <url> | --design-match <plan.json>]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:orchestrator
---

# Close the Loop

Verification loop that checks your work is actually done — not just "compiles", but tested, functional, and visually correct. Three workflows:

- **Story verification** — loop through `.ralph/prd.json` stories, run tests + browser check + visual-diff regression.
- **URL check** — verify a single page end-to-end.
- **Design-match** — iterate on a UI until it matches a reference design, component by component.

## Usage

```
/close-the-loop                                        # Verify all incomplete stories
/close-the-loop --story US-003                         # Verify a single story
/close-the-loop --url http://localhost:3000/settings   # Verify a specific page
/close-the-loop --all                                  # Verify everything, including already-passed stories

# Design-match: iterate until the live app matches a reference
/close-the-loop --design-match .visual-diff/design-match.json
/close-the-loop --design-match ./nyt-reference.png --url http://localhost:3000  # ad-hoc whole-page
```

## Setup

1. **Find stories** — read `.ralph/prd.json` if it exists, otherwise ask the user what to verify
2. **Detect test framework** — scan for vitest.config, jest.config, pytest.ini, go.mod, Makefile, etc.
3. **Detect dev server** — check package.json scripts for `dev`/`start`/`serve`

## The Story Loop

For each story (or the provided `--url`):

### Step 1: Run Tests

- Detect and run the project's test suite (vitest, jest, pytest, go test, etc.)
- If tests fail, attempt to fix. Re-run. Max 3 fix attempts per story.

### Step 2: Browser Check

- Start the dev server if not already running (`npm run dev`, etc.)
- Use `/playwright-check` to navigate to the relevant page
- Check for console errors, broken layouts, missing content
- If browser tools are unavailable, skip this step and note it in the report

### Step 3: Visual Comparison

- If baseline screenshots or design specs exist in `.visual-diff/baselines/`
- Use `/visual-diff` to compare current screenshot against baseline
- Flag any regressions above the threshold

### Step 4: Verdict

- **Pass** — tests green, no console errors, visuals match. Mark story verified.
- **Fail** — describe what's wrong, attempt fix, re-run from Step 1.
- Max 3 full-loop attempts per story before flagging for human review.

## The Design-Match Loop

Purpose: take a live app and iterate on it until it matches a reference design — per component, not just per page. This is the "does my NYT theme actually look like NYT Connections?" loop.

### Match plan

A design-match plan lives at `.visual-diff/design-match.json` (one per project). Example:

```json
{
  "name": "NYT Connections theme match",
  "url": "http://localhost:3000",
  "threshold": 85,
  "max_iterations": 3,
  "components": [
    {
      "id": "page",
      "selector": null,
      "reference": "./references/nyt-full-page.png",
      "notes": "Overall page layout and typography"
    },
    {
      "id": "word-card",
      "selector": "[data-slot=\"card\"]",
      "reference": "./references/nyt-tile.png",
      "notes": "Tile bg #efefe6, 8px radius, bold uppercase"
    },
    {
      "id": "primary-button",
      "selector": "button[data-variant=\"default\"]",
      "reference": "./references/nyt-button.png"
    },
    {
      "id": "dialog",
      "selector": "[role=\"dialog\"]",
      "reference": { "page": "https://nytimes.com/games/connections", "selector": ".modal" }
    }
  ]
}
```

Each component can reference:
- A local image path
- An HTTP URL (curl-fetched, auth-free only)
- Another live page via `{ page, selector }` for playwright capture on both sides

### Loop

For each component in the plan:

1. **Capture current** — `/playwright-check` navigates to `url`, screenshots the component (selector crop if defined).
2. **Resolve reference** — local path / URL download / live page capture, same as visual-diff.
3. **Diff** — `/visual-diff` runs pixel + Claude vision. Threshold from plan (default 85%).
4. **If below threshold**: read Claude's verdict, propose a targeted fix (CSS var, token, class change). Apply. Loop back to step 1 for *this component only*.
5. **Max iterations per component** — default 3. After that, flag for human review and move on.
6. **If above threshold**: mark matched, move to next component.

The key property: component iteration is independent. Getting `.word-card` right doesn't re-run the `.primary-button` diff. This keeps context focused and avoids thrashing.

### Ad-hoc mode

`/close-the-loop --design-match ./ref.png --url http://localhost:3000` skips the JSON plan, does a single whole-page diff, and iterates up to 3 times.

## Output: Verification Report

### Story mode

```markdown
## Verification Report

| Story | Tests | Browser | Visual | Status |
|-------|-------|---------|--------|--------|
| US-001 | Pass | Pass | Pass | Verified |
| US-002 | Pass | Pass | 92% (below 95%) | FAIL |
| US-003 | Fail (TypeError) | Skipped | Skipped | FAIL |

### Issues Found
- US-002: Button color differs from baseline (#3B82F6 vs #2563EB)
- US-003: TypeError in search handler — fixed on attempt 2, now passing

### Summary
Verified: 2/3 | Failed: 1/3
```

### Design-match mode

```markdown
## Design-Match Report — NYT Connections theme

| Component | Selector | Match | Iterations | Status |
|-----------|----------|-------|------------|--------|
| page | — | 88% | 1 | Matched |
| word-card | [data-slot="card"] | 91% | 2 | Matched (fixed bg #efefe6, radius 8px) |
| primary-button | button[data-variant="default"] | 79% | 3 | Flagged — pill radius present but font-weight 600 vs 700 |
| dialog | [role="dialog"] | 86% | 1 | Matched |

### Fixes Applied
- word-card iter 1 → iter 2: set `--card: #efefe6`, `border-radius: 0.5rem`
- primary-button iter 1 → 2 → 3: added `border-radius: 9999px`, adjusted padding. Still failing on font-weight.

### Flagged for Human
- primary-button — Claude vision says font-weight mismatch, but the relevant CSS var is already set. Might be a font-loading issue (Franklin not loaded). Check network tab.
```

## Integration

- **Ralph** — reads stories from `.ralph/prd.json`, updates `passes` field on verification
- **TDD** — uses same test detection patterns
- **playwright-check** — delegates browser verification + screenshot capture
- **visual-diff** — delegates image comparison (pixel + Claude vision)
- **frontend-design** — if design-match iterations keep failing, consult this skill for token/class guidance

## Rules

1. Always run tests before browser checks — no point checking UI if logic is broken.
2. Never mark a story verified without running at least the test suite.
3. If browser tools are unavailable, note it — don't silently skip verification.
4. Fix attempts should be targeted, not shotgun — read the error (or Claude's visual verdict), understand the cause, change one thing at a time.
5. After 3 failed attempts per component, stop and flag — don't loop forever.
6. In design-match mode, always surface Claude's visual verdict text verbatim in the report. The pixel % alone is never enough to diagnose.
7. Keep per-component screenshots in `.visual-diff/tmp/` with descriptive names so the user can inspect the ones that failed.
