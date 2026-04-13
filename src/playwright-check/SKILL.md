---
name: playwright-check
description: Browser-based verification using Playwright MCP or Claude-in-Chrome. Navigate pages, interact, screenshot, check console errors. Use when you need to check a page, verify UI, take screenshots, or test browser interactions.
argument-hint: <url> [--flow <steps>] [--responsive] [--no-screenshot]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Playwright Check

Browser verification. Navigate to pages, interact with UI, take screenshots, check for console errors.

## Usage

```
/playwright-check http://localhost:3000
/playwright-check http://localhost:3000/settings --flow "click #save-btn, wait 1s, check .toast"
/playwright-check http://localhost:3000 --responsive
```

## Tool Detection

Try browser tools in priority order. Attempt to use each; if it errors, fall back:

1. **Playwright MCP** — `mcp__playwright__` tools (navigate, screenshot, click)
2. **Claude-in-Chrome** — `mcp__claude-in-chrome__` tools
3. **Curl fallback** — `curl -s -o /dev/null -w "%{http_code}"` for basic HTTP checks

State which tool is being used in the output.

## Checks

### Page Load
Navigate to URL, wait for load, screenshot (unless `--no-screenshot`), check console for errors/warnings, verify HTTP 200.

### Interaction Flow (--flow)
Parse comma-separated actions: `click <selector>`, `type <selector> "text"`, `wait <duration>`, `check <selector>`, `submit <selector>`. Screenshot after each action.

### Responsive (--responsive)
Screenshot at 375px (mobile), 768px (tablet), 1440px (desktop). Flag overlapping elements, horizontal scroll, or cut-off content.

## Screenshot Storage

Save to `.playwright-checks/<feature>/` (e.g. `desktop-1440.png`, `after-click-save.png`). Add `.playwright-checks/` to `.gitignore` if not already there.

## Output

```markdown
## Browser Check: [url]
- Tool: Playwright MCP
- Status: 200 OK
- Console errors: none

| Check | Status | Notes |
|-------|--------|-------|
| Page load | Pass | Loaded in 1.2s |
| Console | Pass | No errors |
| Click #save-btn | Pass | Toast appeared |
```

## Rules

1. Always state which tool is being used (Playwright MCP, Chrome, or curl)
2. If no browser tools available, say so clearly — curl cannot verify UI
3. Screenshots are evidence — always save unless `--no-screenshot`
4. Add `.playwright-checks/` to `.gitignore` if missing
