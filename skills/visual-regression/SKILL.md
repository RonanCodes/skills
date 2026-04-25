---
name: visual-regression
description: Wire Playwright screenshot baselines with CI PR-diff comments to protect against silent CSS regressions. Composes with `/ro:playwright-check` (browser tool) and `/ro:visual-diff` (per-image diff). Use after polish work is done and you want to keep it intact.
category: quality-review
argument-hint: [--routes <comma-list>] [--viewports <list>] [--update-baselines]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:adapter
---

# Visual Regression

Playwright's `toHaveScreenshot()` is the cheapest-to-maintain visual regression setup that exists. Baseline PNGs live in the repo, diffs appear as PR comments, false positives are rare if you pin viewport + font + timing.

Visual regression is the safety net for polish work. Without it, a global CSS change silently moves a padding value and nobody notices for three weeks.

## Usage

```
/ro:visual-regression                                  # baseline the default routes
/ro:visual-regression --routes '/,  /how-it-works'     # specific routes
/ro:visual-regression --viewports 'mobile,tablet'      # override default viewport set
/ro:visual-regression --update-baselines               # regen after an intentional design change
```

## What gets wired

1. **`e2e/visual.spec.ts`** — baseline tests per route × viewport.
2. **`playwright.config.ts`** updates — deterministic screenshot config.
3. **`e2e/__screenshots__/`** — baseline PNGs committed to the repo.
4. **GitHub Actions workflow** running on PR with diff artifacts.
5. **PR comment integration** via `bramblex/playwright-report-to-pr-comment` or similar.

## 1. The test file

```ts
// e2e/visual.spec.ts
import { test, expect } from '@playwright/test'

const routes = [
  { path: '/', name: 'home' },
  { path: '/how-it-works', name: 'how-it-works' },
  { path: '/?date=2026-04-12', name: 'home-with-puzzle' },
]

const viewports = [
  { name: 'mobile', width: 390, height: 844 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'desktop', width: 1440, height: 900 },
]

for (const route of routes) {
  for (const vp of viewports) {
    test(`${route.name} @ ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height })
      await page.goto(route.path)

      // Wait for fonts + images to stabilise.
      await page.waitForLoadState('networkidle')
      await page.evaluate(() => document.fonts.ready)

      // Mask anything that changes run-to-run (time, counters, live data).
      await expect(page).toHaveScreenshot(`${route.name}-${vp.name}.png`, {
        fullPage: true,
        mask: [
          page.locator('[data-test="stats-counter"]'),
          page.locator('[data-test="live-timestamp"]'),
        ],
        maxDiffPixels: 100,
      })
    })
  }
}
```

**`mask`** replaces the element with a pink rectangle before the diff. Use for any content that changes between runs (counters, timestamps, random images).

**`maxDiffPixels: 100`** tolerates sub-rendering differences (anti-aliasing, sub-pixel positioning). If the diff exceeds 100 pixels, it fails.

## 2. `playwright.config.ts` determinism

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,      // allow ≤1% pixel diff
      threshold: 0.2,               // per-pixel RGB tolerance
      animations: 'disabled',
      caret: 'hide',
    },
  },
  use: {
    ...devices['Desktop Chrome'],
    locale: 'en-GB',
    timezoneId: 'Europe/Amsterdam',
    colorScheme: 'light',
    // Reduce motion prevents any animation drift.
    reducedMotion: 'reduce',
    // Force same font rendering across macOS dev and Linux CI.
    launchOptions: {
      args: ['--font-render-hinting=none'],
    },
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
```

**Locale + timezone** pinned explicitly. A test running on a CI box in PST with a US locale renders dates differently from local macOS in CET — and the baseline will mismatch.

**`animations: 'disabled'`** pauses CSS animations at their starting frame. Without this, the 300ms fade-in on a toast is the difference between pass and fail depending on how fast CI runs.

## 3. Initial baseline capture

```bash
# Local (macOS):
pnpm exec playwright test e2e/visual.spec.ts --update-snapshots

# Commit the baselines:
git add e2e/__screenshots__
git commit -m "🧪 test: add visual regression baselines"
```

**Capture on Linux via Docker for consistency with CI:**

```bash
# If dev is macOS but CI is Linux, baseline on Linux to avoid font-rendering diff:
docker run --rm --network=host \
  -v $(pwd):/work -w /work \
  mcr.microsoft.com/playwright:v1.48.0-jammy \
  pnpm exec playwright test e2e/visual.spec.ts --update-snapshots
```

This is annoying but necessary. macOS and Linux render fonts differently; the baseline diff will be ~5% even when nothing changed. Either baseline on Linux (docker above), or run CI only on macOS runners (expensive).

## 4. GitHub Actions workflow

```yaml
# .github/workflows/visual-regression.yml
name: Visual Regression
on: [pull_request]

jobs:
  visual:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm build
      - name: Run visual tests
        run: pnpm exec playwright test e2e/visual.spec.ts
      - name: Upload diff on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: visual-diff
          path: test-results/
          retention-days: 7
      - name: Comment on PR
        if: failure()
        uses: mshick/add-pr-comment@v2
        with:
          message: |
            🖼️ Visual regression failed. Download the `visual-diff` artifact to see what changed.

            If the change is intentional, run:
            ```
            pnpm exec playwright test e2e/visual.spec.ts --update-snapshots
            git add e2e/__screenshots__
            git commit
            ```
```

The failure artifact includes `expected.png`, `actual.png`, and `diff.png` for every failing test. Reviewer opens the diff, decides intentional vs regression, and either approves or asks for a fix.

## 5. Updating baselines after intentional change

```bash
# After a design change, regenerate baselines:
pnpm exec playwright test e2e/visual.spec.ts --update-snapshots
git diff --stat e2e/__screenshots__

# Review the changes in the PR using something like GitHub's image compare view.
git add e2e/__screenshots__
git commit -m "🎨 style: update visual regression baselines after header redesign"
```

**Commit message discipline matters.** Reviewers should be able to audit why baselines changed 3 months later.

## Picking what to baseline

**High-value routes to baseline:**
- Homepage / landing page.
- Primary feature flow (e.g. puzzle view, checkout page, dashboard).
- Any page that renders data from a database (empty state, populated state).
- `/how-it-works`, `/pricing`, marketing pages — silent regression here hurts conversion.

**Low-value routes (skip):**
- Admin pages — internal, not sensitive to regression.
- Auth flows — tested at a different layer.
- Error pages (404, 500) — usually fine; baselining creates more maintenance than value.

**Viewport strategy:**
- Mobile (390×844 — iPhone 14) — most traffic.
- Desktop (1440×900) — dev checks.
- Tablet only if the app renders meaningfully differently at tablet widths.

## Complementary tool: `/ro:visual-diff`

`/ro:visual-diff` does per-image pixel diff. Use it for one-off "does this PR change this screenshot" checks, outside Playwright. This skill (`/ro:visual-regression`) composes those diffs into an always-on CI gate.

```
/ro:visual-diff before.png after.png              # one-off check
/ro:visual-regression                              # always-on, in CI
```

## Gotchas

- **Flakiness from fonts.** Baseline on the same OS as CI (Linux via Docker) or the diff-pixel ratio will eat you.
- **Flakiness from timestamps.** Any UI showing "now" or relative time needs `mask: [...]` or a frozen clock (`page.clock.install({ time: '2026-04-12T10:00:00Z' })`).
- **Flakiness from API data.** Tests that render real data are flaky. Mock the API at the fetch layer (`page.route('**/api/**', (route) => route.fulfill({ json: fixture }))`).
- **Image size explosion.** A full-page screenshot on desktop 4k is ~1-2 MB. Repo can grow fast. Consider `fullPage: false` + scoped selectors for sub-components if size matters.
- **Baselines in merge conflicts.** Binary PNG conflicts are impossible to resolve in git. Rebase, regenerate baselines, recommit.
- **Ignoring dynamic content.** If you mask too much, the test stops catching real changes. Masks should cover only truly random regions.
- **Running tests in parallel.** Playwright parallelises by default; screenshots can occasionally collide on scroll position. Use `test.describe.configure({ mode: 'serial' })` if flakiness correlates with parallel runs.

## When NOT to use visual regression

- Early-stage apps with rapid design iteration. You'll regenerate baselines every PR — noise exceeds signal.
- Pure-backend projects. Visual regression is for UI.
- Marketing sites where content changes daily. Move to a CMS-level approval workflow instead.

## Rules

- **Baseline intentionally.** Every baseline in the repo is a contract. If it was captured by accident, it's technical debt.
- **Update baselines in dedicated PRs when the change is large.** Mixing a visual-regression update with feature work makes review harder.
- **Don't tolerate flaky tests.** A flaky visual test trains the team to ignore failures. Fix or delete.
- **Review diffs.** Opening the `diff.png` artifact before merging is non-negotiable. Don't just click "update baselines".
- **Pin everything.** Locale, timezone, color scheme, font rendering, animation state. Any unpinned variable is future flake.

## See also

- `/ro:app-polish` — umbrella; this is check #8
- `/ro:playwright-check` — underlying browser tool used by this skill
- `/ro:visual-diff` — per-image diff primitive this skill composes
- `/ro:design-system-audit` — runs before visual regression to catch design-token drift
- `/ro:accessibility-ci` — complementary; focus-ring visual changes are caught here
- Playwright screenshots docs: https://playwright.dev/docs/test-snapshots
