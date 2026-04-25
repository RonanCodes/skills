---
name: app-polish
description: Post-ship launch-ready polish audit. Walks a freshly-shipped web app against the ten-point launch-polish checklist (analytics, stats surface, OG images, PWA, SEO, keyboard, accessibility, visual regression, API docs, craft signals) and routes to the dedicated sub-skill for each gap. Use right after `/ro:cf-ship` / `/ro:fly-deploy` / `/ro:gh-ship`, or before a Product Hunt / Show HN launch.
category: quality-review
argument-hint: [--app <dir>] [--only <checks>] [--skip <checks>] [--fix]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:orchestrator
---

# App Polish

Pre-launch audit for a web app. Walks ten checks in order; for each gap, routes to a dedicated sub-skill that actually does the work. Designed to run on the Friday before a Tuesday / Wednesday launch.

## Usage

```
/ro:app-polish                          # audit current repo, report gaps
/ro:app-polish --app ./connections-helper
/ro:app-polish --only analytics,og      # run only a subset
/ro:app-polish --skip pwa,visual-reg    # skip items not applicable
/ro:app-polish --fix                    # auto-invoke each sub-skill for gaps found
```

Report format per check:

```
[✓|⚠|✗] <check> — <one-line finding>
  Sub-skill: /ro:<skill>
  Effort: <S|M|L>
  Launch impact: <high|medium|low>
```

## The ten checks

Run in this order (earlier items compound into later ones — e.g. analytics events need to exist before visual regression baselines get captured).

### 1. Analytics event instrumentation — `/ro:posthog`

Is there an analytics provider wired up? Are custom events fired on share handlers, CTAs, forms? Is there a typed `track()` wrapper?

**Detect:**
```bash
grep -rn "posthog.init\|plausible.init\|Mixpanel" src 2>&1 | head -3
grep -rn "posthog.capture\|track(" src 2>&1 | wc -l
```

**Verdict rules:**
- ✗ if no provider wired.
- ⚠ if provider wired but <3 custom events. Autocapture alone leaves the launch funnel blind.
- ✓ if typed `track()` wrapper exists + share/cta/form events fired.

**Fix:** invoke `/ro:posthog install` if missing, then see the "Launch-ready event instrumentation" section for the event checklist.

### 2. Stats / social-proof surface

Is there a stats endpoint (counts, usage, reach) and is it displayed in the UI? Numbers on a page are a low-cost trust signal.

**Detect:**
```bash
grep -rn "/api/stats\|/api/metrics\|/api/health" src --include='*.ts' --include='*.tsx' | head
grep -rn "toLocaleString\|stats\." src/routes src/components 2>&1 | head
```

**Verdict rules:**
- ⚠ if endpoint exists but no UI reads it. Common oversight.
- ✓ if surfaced in footer, /how-it-works, or a stats card.

**Fix:** add a `StatsBanner` component (see `seo-launch-ready` for template) that `fetch('/api/stats')` + renders counts with `toLocaleString()`. Keep it `aria-live="polite"`.

### 3. Dynamic OG images per URL — `/ro:og-image-dynamic`

Every share-target URL should unfurl with a distinct Open Graph image. Generic static OG kills click-through on Twitter/Reddit/LinkedIn previews.

**Detect:**
```bash
grep -rn 'og:image\|twitter:image' src 2>&1 | head
ls -la public/*.png 2>&1 | head
```

**Verdict:**
- ⚠ if only one static `og-image.png` for all URLs.
- ✓ if dynamic endpoint at `/api/og.png` (or similar) exists and meta tags reference a per-URL variant.

**Fix:** `/ro:og-image-dynamic` — Satori + Cloudflare Workers or Vercel OG template.

### 4. PWA installability — `/ro:pwa-install`

Daily-return apps (puzzles, habit trackers, dashboards) should be installable. Replaces the need for an email list.

**Detect:**
```bash
ls public/manifest.json public/manifest.webmanifest 2>&1
ls public/sw.js public/service-worker.js 2>&1
grep -rn 'link.*rel="manifest"' src 2>&1 | head -3
```

**Verdict:**
- ⚠ if no manifest and the app is return-traffic-shaped (daily utility, dashboard).
- ✓ if manifest + service worker + install prompt.

**Fix:** `/ro:pwa-install`.

### 5. SEO readiness — `/ro:seo-launch-ready`

Sitemap, robots.txt, JSON-LD structured data, canonical URLs, meta tags complete across all routes.

**Detect:**
```bash
ls public/sitemap.xml public/robots.txt 2>&1
grep -rn 'application/ld+json\|canonical\|og:title' src 2>&1 | head
```

**Verdict:**
- ⚠ if missing sitemap/robots, or JSON-LD absent, or OG tags only on root.
- ✓ if all four present.

**Fix:** `/ro:seo-launch-ready`.

### 6. Keyboard shortcuts — `/ro:keyboard-shortcuts`

Power-user signal that drives screencasts and portfolio respect. Especially for utility apps.

**Detect:**
```bash
grep -rn "addEventListener.*keydown\|useHotkeys\|useKeyboard" src 2>&1 | head -3
```

**Verdict:**
- ⚠ if no global key handler and the app has >3 primary actions.
- ✓ if `?` brings up a shortcut list and main actions have bindings.

**Fix:** `/ro:keyboard-shortcuts`.

### 7. Accessibility + CI — `/ro:accessibility-ci`

`aria-live` regions on async state, focus management in modals, colour contrast, `axe-core` unit + e2e, Lighthouse CI.

**Detect:**
```bash
grep -rn 'aria-live\|aria-label\|role=' src 2>&1 | wc -l
grep -l 'axe-core\|@axe-core/playwright\|jest-axe' package.json 2>&1
ls .github/workflows 2>&1 | head
```

**Verdict:**
- ⚠ if no `aria-live` on any async region, or `axe-core` not in deps.
- ✓ if a11y unit tests + Lighthouse CI + axe e2e all run on PR.

**Fix:** `/ro:accessibility-ci`.

### 8. Visual regression CI — `/ro:visual-regression`

Playwright screenshot baselines + PR diff comments. Protects the polish work from silent CSS regressions.

**Detect:**
```bash
grep -rn 'toHaveScreenshot\|pixelmatch\|percy' tests e2e 2>&1 | head
```

**Verdict:**
- ⚠ if Playwright installed but no `toHaveScreenshot` assertions.
- ✓ if visual baselines committed + CI workflow comments PR on diff.

**Fix:** `/ro:visual-regression`.

### 9. API documentation link

Scalar / Swagger / Redoc docs exposed and linked from the footer. Craft signal.

**Detect:**
```bash
grep -rn '/api/docs\|/api/openapi\|@scalar\|swagger-ui' src 2>&1 | head
grep -rn 'footer.*API\|footer.*docs' src 2>&1 | head
```

**Verdict:**
- ⚠ if docs exist but not linked from a visible page.
- ✓ if footer or `/how-it-works` has a visible link.

**Fix:** add `<a href="/api/docs" target="_blank">API</a>` in the footer.

### 10. Craft signals

Miscellaneous polish: `robots` meta, canonical URL, 404 page, `aria-label` on all icon-only buttons, environment-specific favicon (optional), skip-to-content link.

**Detect:**
```bash
grep -rn 'skip.*content\|skip.*main' src 2>&1 | head
find src -name 'not-found*' -o -name '404*' 2>&1 | head
grep -rn '<Button[^>]*onClick' src/App.tsx | grep -v 'aria-label\|title' | head
```

**Verdict:**
- ⚠ if icon-only buttons without `aria-label`, or no 404 route.
- ✓ if all present.

**Fix:** spot-fix, no dedicated sub-skill.

## Running the audit

```bash
#!/usr/bin/env bash
# /ro:app-polish implementation sketch
set -euo pipefail

APP=${1:-.}
cd "$APP"

echo "=== App Polish Audit: $(pwd) ==="
echo

# 1. Analytics
if grep -rn "posthog.init\|plausible.init" src >/dev/null 2>&1; then
  events=$(grep -rn "track(\|posthog.capture" src 2>/dev/null | wc -l | tr -d ' ')
  if [ "$events" -ge 3 ]; then
    echo "[✓] analytics — provider + $events custom event call sites"
  else
    echo "[⚠] analytics — provider wired but only $events custom events (need ≥3)"
    echo "    Sub-skill: /ro:posthog  · Effort: S  · Impact: high"
  fi
else
  echo "[✗] analytics — no provider detected"
  echo "    Sub-skill: /ro:posthog  · Effort: S  · Impact: high"
fi

# ...(repeat for 2-10)
```

The `--fix` flag invokes the sub-skill for each ⚠ or ✗ in sequence, with a confirmation prompt per skill.

## Interaction with existing skills

| Existing skill | Role in polish |
| --- | --- |
| `/ro:close-the-loop` | Runs the app's own test suite; polish is what to run on top of tests passing. |
| `/ro:playwright-check` | Underlying browser tool; `visual-regression` uses it for baselines. |
| `/ro:visual-diff` | Per-image pixel diff; `visual-regression` composes this into a CI flow. |
| `/ro:design-system-audit` | Deeper audit of colour tokens, spacing, typography. Run alongside `app-polish` for the visual axis. |
| `/ro:security-audit` | Secrets, headers, rate limits, CSP. Complementary to polish. |
| `/ro:cf-ship` / `/ro:fly-deploy` / `/ro:gh-ship` | What ships the app; `app-polish` runs right after a successful ship, before the marketing beat. |

## When to run

- **Right after ship**, before the launch-plan's Week 1 work begins. Gaps compound: instrumentation needs to exist before you can measure baselines.
- **Before Product Hunt / Show HN**. The polish gaps are visible to the audience at exactly the moment blast radius is highest.
- **After a big refactor**. Catches regressions in visual/a11y/SEO invariants that aren't covered by unit tests.

## Rules

- **Report before fixing.** Always show the audit verdict first, even with `--fix`. The user should pick which gaps to close.
- **Effort tiers are honest.** S = ≤1h, M = 1-3h, L = half-day+. Don't soft-estimate.
- **Launch impact ≠ effort.** Some L-effort items (PWA, dynamic OG) are high-impact; some S items are low-impact (craft signals). Rank by impact × time-to-launch, not effort.
- **Order matters.** Instrument analytics *before* running visual regression — otherwise baselines capture a pre-instrumentation state.
- **Don't run on every commit.** This is a pre-launch / pre-demo skill, not a CI gate. `/ro:close-the-loop` is the per-PR gate.

## See also

- `/ro:posthog` — analytics + event instrumentation
- `/ro:og-image-dynamic` — per-URL Open Graph images
- `/ro:pwa-install` — manifest + service worker
- `/ro:seo-launch-ready` — sitemap + JSON-LD + meta
- `/ro:keyboard-shortcuts` — global key handler
- `/ro:accessibility-ci` — axe + Lighthouse + a11y unit tests
- `/ro:visual-regression` — Playwright screenshot baselines
- `/ro:design-system-audit` — visual invariants
- `/ro:security-audit` — CSP, secrets, rate limiting
- `/ro:close-the-loop` — per-PR verification, complements polish
