---
name: browser-dev
description: Lightweight browser automation via custom scripts. Use when Playwright MCP or Claude-in-Chrome is unavailable, or for building reusable browser check flows.
category: browser-visual
argument-hint: <url> [--screenshot] [--check] [--script <path>] [--flow "description"]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Browser Dev

Write and run Node.js browser automation scripts using Playwright as a library. No MCP required. Scripts are saved for reuse.

## Usage

```
/browser-dev http://localhost:3000 --screenshot
/browser-dev http://localhost:3000 --check
/browser-dev --script .browser-dev/login-flow.js
/browser-dev http://localhost:3000 --flow "click Sign In, fill email, fill password, submit, check dashboard loads"
```

## Dependency Check

Before running, detect the automation library:

```bash
node -e "require('playwright')" 2>/dev/null && echo "playwright" || \
node -e "require('puppeteer')" 2>/dev/null && echo "puppeteer" || echo "none"
```

If **none**: tell the user to install one — `npm install -D playwright && npx playwright install chromium`. Prefer Playwright (cross-browser, auto-waiting, better API). Do NOT proceed without a library installed.

## Built-in Flows

| Flag | Action |
|------|--------|
| `--screenshot <url>` | Full-page screenshot, saved to `.browser-dev/screenshots/<timestamp>.png` |
| `--check <url>` | Verify page loads (200), no console errors, no uncaught exceptions. Pass/fail table. Exit 1 on fail |
| `--script <path>` | Run an existing script: `node <path> [args]`. No generation needed |
| `--flow "desc"` | Generate a custom script from natural-language description, save to `.browser-dev/flows/<slug>.js`, run it |

## Script Template

All generated scripts follow this pattern:

```javascript
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', err => errors.push(err.message));
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });

  // --- flow logic here ---

  await browser.close();
  if (errors.length) { console.error('Errors:', errors); process.exit(1); }
})();
```

## File Layout

```
.browser-dev/
├── screenshots/       # --screenshot output
├── flows/             # saved --flow scripts
└── scripts/           # user's custom scripts
```

Add `.browser-dev/` to `.gitignore` if not already present.

## Rules

1. Always check for `playwright` or `puppeteer` before generating scripts — adapt `require()` to whichever is installed
2. If both are installed, prefer Playwright
3. Scripts must be self-contained — no imports beyond the automation library
4. Always set `headless: true` unless the user explicitly asks for headed mode
5. Print clear pass/fail results to stdout — Claude reads the output
6. Save every generated script so users can re-run with `--script`
7. Use `waitUntil: 'networkidle'` for page loads by default
8. Set a 30-second timeout on all navigations
