---
name: browser-cookies
description: Extract cookies for a domain from the user's browser (Firefox, Brave, Chrome, Arc, Chromium, Edge). Reads ROBROWSER default from ~/.config/ro/defaults.env. Used by scraping skills that need an authenticated session. Supersedes firefox-cookies.
category: infra
argument-hint: <domain> [--browser brave|chrome|arc|chromium|edge|firefox|auto] [--format header|json|jar]
allowed-tools: Bash(sqlite3 *) Bash(uv *) Bash(python3 *) Read Write
content-pipeline:
  - pipeline:scan
  - platform:multi
  - role:primitive
---

# Browser Cookies

Pull cookies for a specific domain from the user's logged-in browser session. Supports:

- **Firefox** — reads `cookies.sqlite` directly (no decryption needed)
- **Chromium family** (Brave, Chrome, Arc, Chromium, Edge) — via `browser_cookie3`, which decrypts using the macOS Keychain (prompts the first time)

Output formats: shell-safe `Cookie:` header (default), JSON, or a raw name/value list.

## Usage

```
/ro:browser-cookies linkedin.com                        # uses ROBROWSER default (brave for this user)
/ro:browser-cookies linkedin.com --browser firefox
/ro:browser-cookies x.com --format json
```

## Resolving the browser

Priority:
1. `--browser` flag
2. `ROBROWSER` from `~/.config/ro/defaults.env`
3. Auto-detect: first of `brave`, `chrome`, `arc`, `firefox` with a cookies file for the requested domain.

## Execution

Single entry point: `scripts/get.py`. Invoke with `uv` so `browser_cookie3` is auto-provisioned:

```bash
uv run --with browser-cookie3 --with requests python3 \
  /path/to/skills/browser-cookies/scripts/get.py <domain> [flags]
```

Firefox path uses stdlib only (sqlite3). Chromium path needs `browser_cookie3`.

## Keychain prompt (first time on Chromium)

macOS will prompt: *"python3 wants to use the 'Brave Safe Storage' key in your keychain."* Click **Always Allow**. Without approval, decryption silently returns zero cookies.

## Output shape

### `--format header` (default)

```
Cookie: li_at=AQE...; JSESSIONID="ajax:..."; bcookie=v=2&...
```

One line. Safe to `export COOKIE_HEADER="$(...)"` and pass to `curl -H`.

### `--format json`

```json
[
  {"name": "li_at", "value": "AQE...", "domain": ".linkedin.com", "expires": 1780000000}
]
```

### `--format jar`

Tab-separated `name<TAB>value` — convenient for shell parsing.

## Security

- Domain-scoped — never dumps all cookies.
- Never writes cookie values to disk. Temp Firefox DB copy deleted after reading.
- Callers must never log or commit the output.

## Dependencies

- **macOS** only for now. Paths hardcoded to `~/Library/Application Support/...`.
- `sqlite3` (Firefox path) — preinstalled
- `uv` — for auto-provisioning `browser_cookie3`. Install: `brew install uv`

## See also

- `ro:firefox-cookies` — narrower legacy skill (Firefox only). Deprecated; prefer this.
- `ro:linkedin-scan`, `ro:linkedin-voyager` — primary callers.
