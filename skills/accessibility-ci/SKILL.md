---
name: accessibility-ci
description: Ship accessibility as a CI gate, not a hope. Wires axe-core unit tests (jest-axe or vitest-axe), @axe-core/playwright e2e, Lighthouse CI, aria-live regions for async state, and focus management in modals. Use right after `/ro:cf-ship` as part of `/ro:app-polish` check #7.
category: quality-review
argument-hint: [--runner vitest|jest] [--lighthouse] [--skip-e2e]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:adapter
---

# Accessibility CI

Ship accessibility checks as code, not as a one-time audit. The three-layer stack catches ~80% of real issues:

1. **Unit** — `vitest-axe` / `jest-axe` on critical components.
2. **E2E** — `@axe-core/playwright` on key flows.
3. **Lighthouse CI** — performance + a11y thresholds as PR gates.

Manual testing (screen reader, keyboard navigation) catches the rest. This skill wires the automated layers; the manual layer is a checklist, not automation.

## Usage

```
/ro:accessibility-ci                          # full install: unit + e2e + lighthouse + aria patterns
/ro:accessibility-ci --runner jest            # jest-axe instead of vitest-axe
/ro:accessibility-ci --lighthouse             # add Lighthouse CI only
/ro:accessibility-ci --skip-e2e               # skip Playwright axe wiring
```

## What gets wired

1. **`vitest-axe` or `jest-axe`** with a helper for component-level tests.
2. **`@axe-core/playwright`** for e2e on critical routes.
3. **`@lhci/cli`** with PR thresholds for a11y + performance.
4. **GitHub Actions workflow** running all three on PR.
5. **`aria-live` regions** on async state containers (loading, error, fetched content).
6. **Focus management** in modals and route transitions.

## 1. Unit-level axe

### Vitest

```bash
pnpm add -D vitest-axe axe-core @testing-library/react
```

```ts
// src/test/axe-helper.ts
import { axe, toHaveNoViolations } from 'vitest-axe'
import { expect } from 'vitest'

expect.extend({ toHaveNoViolations })

export async function expectNoA11yViolations(container: HTMLElement) {
  const results = await axe(container)
  expect(results).toHaveNoViolations()
}
```

Test example:

```tsx
// src/components/ShareButton.test.tsx
import { render } from '@testing-library/react'
import { ShareButton } from './ShareButton'
import { expectNoA11yViolations } from '@/test/axe-helper'

test('ShareButton is accessible', async () => {
  const { container } = render(<ShareButton puzzleDate="2026-04-12" />)
  await expectNoA11yViolations(container)
})
```

**What to cover:**
- Every primary CTA / form.
- Anything with `role=` or `aria-*` attributes you added manually.
- Modal / dialog components (focus trap is a common bug source).
- Icon-only buttons (to catch missing `aria-label`).

**What NOT to cover:** every leaf component. Axe is fast but it's not the unit test's job to re-check every render.

## 2. E2E axe with Playwright

```bash
pnpm add -D @axe-core/playwright
```

```ts
// e2e/accessibility.spec.ts
import { test, expect } from '@playwright/test'
import AxeBuilder from '@axe-core/playwright'

const routes = ['/', '/how-it-works', '/api/docs']

for (const route of routes) {
  test(`a11y: ${route}`, async ({ page }) => {
    await page.goto(route)
    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
      .analyze()
    expect(results.violations).toEqual([])
  })
}
```

**Tag choice matters.** `wcag2aa` is the usual bar. Skipping `wcag2aaa` (stricter) is fine — almost nothing passes AAA without deliberate tradeoffs.

**Common false positives:**
- `color-contrast` on disabled buttons — axe flags these. Use `.exclude('[disabled]')` if the contrast is deliberate per your design system.
- `region` on landmarks — if your app is a single-page utility, axe may want a `<main>` wrapper.

## 3. Lighthouse CI

```bash
pnpm add -D @lhci/cli
```

```json
// lighthouserc.json
{
  "ci": {
    "collect": {
      "startServerCommand": "pnpm preview",
      "url": ["http://localhost:4173/", "http://localhost:4173/how-it-works"],
      "numberOfRuns": 3
    },
    "assert": {
      "assertions": {
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "categories:best-practices": ["warn", { "minScore": 0.9 }],
        "categories:seo": ["warn", { "minScore": 0.9 }],
        "categories:performance": ["warn", { "minScore": 0.8 }]
      }
    },
    "upload": {
      "target": "temporary-public-storage"
    }
  }
}
```

Accessibility score as `error` at 0.95 means the PR blocks on regression. Other categories as `warn` lets the team see scores without failing builds on routine fluctuation.

## 4. GitHub Actions

```yaml
# .github/workflows/accessibility.yml
name: Accessibility
on: [pull_request]

jobs:
  a11y:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm test:unit
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm build
      - run: pnpm exec playwright test e2e/accessibility.spec.ts
      - run: pnpm exec lhci autorun
```

`pnpm test:unit` covers the vitest-axe assertions; the Playwright step covers e2e axe; Lighthouse runs last against the built app.

## 5. `aria-live` on async state

Any region that updates after initial render (loading spinner → content, error messages, toast notifications) needs `aria-live` so screen readers announce the change.

```tsx
<div role="status" aria-live="polite" aria-busy={isLoading}>
  {isLoading && <span>Loading definitions…</span>}
  {error && <span role="alert">Failed to load: {error.message}</span>}
  {definitions && <DefinitionsList items={definitions} />}
</div>
```

**`polite` vs `assertive`:**
- `polite` waits for the user to finish what they're saying. Use for most updates.
- `assertive` interrupts. Use only for errors or urgent alerts (`role="alert"` is already `assertive`).

**`aria-busy` toggles off announcements during active loads** so the screen reader doesn't read every progressive render.

## 6. Focus management

### On modal open → trap, on close → return

Most dialog primitives (Radix Dialog, Headless UI Dialog) handle this. If hand-rolling:

```tsx
const triggerRef = useRef<HTMLButtonElement>(null)
const dialogRef = useRef<HTMLDivElement>(null)

useEffect(() => {
  if (open) {
    dialogRef.current?.querySelector<HTMLElement>('[data-autofocus]')?.focus()
  } else {
    triggerRef.current?.focus()
  }
}, [open])
```

### On route transition → announce + move focus to `<main>`

TanStack Router:

```tsx
// src/routes/__root.tsx
import { useEffect } from 'react'
import { useRouter } from '@tanstack/react-router'

function FocusManager() {
  const router = useRouter()
  useEffect(() => {
    const unsub = router.subscribe('onResolved', () => {
      document.getElementById('main-content')?.focus()
    })
    return unsub
  }, [router])
  return null
}
```

With `<main id="main-content" tabIndex={-1}>` in the shell.

## Skip-to-content link

First focusable element on the page should be a skip link:

```tsx
<a
  href="#main-content"
  className="sr-only focus:not-sr-only focus:absolute focus:top-0 focus:left-0 focus:p-2 focus:bg-white focus:z-50"
>
  Skip to main content
</a>
```

Invisible until focused (via tab). Every page should have one.

## Manual checks (not automatable)

- **Keyboard-only navigation.** Tab through every page without a mouse. Can you reach every interactive element? Is focus visible? Can you dismiss every modal with Esc?
- **Screen reader spot-check.** VoiceOver (Cmd+F5 on macOS) or NVDA (free, Windows). Does each page read in a logical order?
- **200% zoom.** Set the browser to 200% zoom. Does the layout still work? (Axe won't catch this.)
- **Reduce motion.** macOS System Preferences → Accessibility → Display → Reduce Motion. Do your animations respect `prefers-reduced-motion`?

## Common violations + fixes

| Violation | Fix |
|---|---|
| `button-name` | Icon-only button missing `aria-label`. Add `aria-label="Share"`. |
| `color-contrast` | Text too light on background. Darken or thicken the text, don't just add bold. |
| `label` | Input missing a label. Wrap in `<label>` or use `aria-labelledby`. |
| `image-alt` | `<img>` without `alt`. Decorative → `alt=""`, informative → descriptive alt. |
| `landmark-one-main` | No `<main>` element. Wrap the main content. |
| `heading-order` | Skipping heading levels (h1 → h3). Use semantic levels, style with CSS. |
| `aria-valid-attr-value` | Typo'd aria attribute value. Usually `aria-expanded="true"` vs `aria-expanded={true}` in JSX. |

## Rules

- **A11y score is a PR gate, not a backlog item.** If it fails, the PR fails.
- **Catch at the lowest layer possible.** Vitest-axe catches `aria-label` typos before Playwright or Lighthouse ever run.
- **Don't over-rely on axe.** Axe detects 30-40% of real issues. The rest require human review.
- **Fix, don't disable.** If you're tempted to `disabledRules: ['color-contrast']`, first ask whether the design is wrong.
- **Test components in their rendered state, not their source.** An `<input>` that looks labelled in JSX may not be — check the rendered DOM.

## See also

- `/ro:app-polish` — umbrella; this is check #7
- `/ro:keyboard-shortcuts` — complementary; focus + keyboard nav live together
- `/ro:visual-regression` — catches focus-ring regressions that axe misses
- `/ro:playwright-check` — the underlying browser tool
- axe-core rule reference: https://github.com/dequelabs/axe-core/blob/master/doc/rule-descriptions.md
- WebAIM contrast checker: https://webaim.org/resources/contrastchecker/
- Deque University: https://dequeuniversity.com/ (most thorough WCAG training)
