---
name: tdd
description: Test-driven development with red-green-refactor cycles and vertical slices. Use when implementing features test-first, doing TDD, or working through a story.
argument-hint: <feature-or-story>
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# TDD

Implement features using strict red-green-refactor cycles. Write the test first. Always.

## Usage

```
/tdd "add search endpoint with fuzzy matching"
/tdd --story US-003
```

If `--story` is passed, read the story from `.ralph/prd.json` for requirements and acceptance criteria.

## Detect the Project

Before writing anything, detect:

1. **Test framework** — scan for jest.config, vitest.config, pytest.ini, go.mod, playwright.config, etc.
2. **Test conventions** — find existing test files to match naming (*.test.ts, *.spec.ts, *_test.go, test_*.py)
3. **Test command** — check package.json scripts, Makefile, or equivalent
4. **Source structure** — understand where source and test files live

If no test setup exists, ask the user which framework to use and set it up.

## The Cycle

Repeat for each vertical slice:

### 1. Red — Write a Failing Test

- Break the feature into the thinnest possible vertical slice
- Write ONE test that defines expected behavior for that slice
- Run the test — it MUST fail
- If it passes, the test is not testing anything new — rewrite it

### 2. Green — Make It Pass

- Write the MINIMUM code to make the test pass
- No extra features, no future-proofing, no "while I'm here" additions
- Run the test — it MUST pass

### 3. Refactor — Clean Up

- Improve naming, extract duplication, simplify logic
- Run tests after EACH change — they must stay green
- Do NOT add new behavior during refactor

## Vertical Slices

Each cycle implements a thin end-to-end slice, not a horizontal layer.

**Good slices** (thin, vertical, testable):
- Search endpoint exists and returns 200 with results
- Search filters by category and returns filtered results
- UI renders search input and displays results from API

**Bad slices** (thick, horizontal):
- Build the entire database layer
- Implement all API endpoints
- Create all UI components

## After Each Cycle

Report:

```
## Cycle N: [slice description]
- RED: [test written, confirmed failing]
- GREEN: [code written, test passing]
- REFACTOR: [what was cleaned up]
- Status: N of ~M slices complete
```

## Integration with Ralph

If working on a story from `.ralph/prd.json`, update the story's `passes` field and append progress to `.ralph/progress.txt` after all slices are complete.

## Rules

1. Never write implementation before the test
2. Never write more than one test at a time
3. Never skip the red step — seeing the test fail proves it tests something real
4. Keep each cycle under 15 minutes of work — if it's bigger, split the slice
5. If stuck, step back and check if the slice is too big
