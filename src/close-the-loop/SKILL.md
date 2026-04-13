---
name: close-the-loop
description: Automated verification loop that ensures work is done — tests pass, UI works, screenshots match designs. Use when you want to verify stories, check everything works, close the loop, or run acceptance checks.
argument-hint: [--all | --story <id> | --url <url>]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Close the Loop

Verification loop that checks your work is actually done — not just "compiles", but tested, functional, and visually correct. Loops through stories, verifies each one, and keeps going until everything passes.

## Usage

```
/close-the-loop              # Verify all incomplete stories
/close-the-loop --story US-003  # Verify a single story
/close-the-loop --url http://localhost:3000/settings  # Verify a specific page
/close-the-loop --all        # Verify everything, including already-passed stories
```

## Setup

1. **Find stories** — read `.ralph/prd.json` if it exists, otherwise ask the user what to verify
2. **Detect test framework** — scan for vitest.config, jest.config, pytest.ini, go.mod, Makefile, etc.
3. **Detect dev server** — check package.json scripts for `dev`/`start`/`serve`

## The Loop

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

## Output: Verification Report

After all stories are checked, produce:

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

## Integration

- **Ralph** — reads stories from `.ralph/prd.json`, updates `passes` field on verification
- **TDD** — uses same test detection patterns
- **playwright-check** — delegates browser verification
- **visual-diff** — delegates screenshot comparison

## Rules

1. Always run tests before browser checks — no point checking UI if logic is broken
2. Never mark a story verified without running at least the test suite
3. If browser tools are unavailable, note it — don't silently skip verification
4. Fix attempts should be targeted, not shotgun — read the error, understand the cause
5. After 3 failed attempts, stop and report — don't loop forever
