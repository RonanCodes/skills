---
name: firefox-cookies
description: Extract cookies from Firefox for authenticated web scraping. Reads cookies.sqlite for a specific domain. macOS only.
category: browser-visual
user-invocable: false
allowed-tools: Bash(sqlite3 *) Bash(ls *) Bash(find *) Bash(cp *) Bash(rm *) Read
---

# Firefox Cookie Extractor

Extract cookies from Firefox's local storage for a given domain. Used by other skills (like ingest-linkedin) for authenticated fetching.

## Usage

Called by other skills with a target domain. Returns a `Cookie:` header string.

## Step 1: Find Firefox Profile

Locate the Firefox profile directory on macOS:
```bash
PROFILES_DIR="$HOME/Library/Application Support/Firefox/Profiles"
# Find the most recently modified profile with a cookies.sqlite
PROFILE_DIR=$(ls -td "$PROFILES_DIR"/*/ 2>/dev/null | while read dir; do
  [ -f "$dir/cookies.sqlite" ] && echo "$dir" && break
done)
```

If no Firefox profile or cookies.sqlite is found:
- Report: "Firefox cookies.sqlite not found. Is Firefox installed and has been used to log in to <domain>?"
- Return empty/error — let the calling skill handle the fallback.

## Step 2: Copy Database

Firefox locks cookies.sqlite while running. Copy to a temp location:
```bash
cp "$PROFILE_DIR/cookies.sqlite" /tmp/llm-wiki-firefox-cookies.sqlite
# Also copy the WAL file if it exists (contains recent writes)
[ -f "$PROFILE_DIR/cookies.sqlite-wal" ] && \
  cp "$PROFILE_DIR/cookies.sqlite-wal" /tmp/llm-wiki-firefox-cookies.sqlite-wal
```

## Step 3: Query Cookies

Extract cookies for the requested domain:
```bash
sqlite3 /tmp/llm-wiki-firefox-cookies.sqlite \
  "SELECT name, value FROM moz_cookies
   WHERE host LIKE '%<domain>%'
   AND expiry > strftime('%s','now')
   ORDER BY name;"
```

The `expiry > strftime('%s','now')` filter skips expired cookies.

## Step 4: Format Cookie Header

Build a standard `Cookie:` header string from the results:
```
Cookie: name1=value1; name2=value2; name3=value3
```

If the query returns zero rows:
- Report: "No cookies found for <domain>. Make sure you're logged in to <domain> in Firefox."
- Return empty — let the calling skill handle the fallback.

## Step 5: Cleanup

Remove the temp copy:
```bash
rm -f /tmp/llm-wiki-firefox-cookies.sqlite /tmp/llm-wiki-firefox-cookies.sqlite-wal
```

## Security

- **Domain-scoped:** Only extract cookies for the specifically requested domain — never dump all cookies.
- **No logging:** Never write raw cookie values to wiki pages, raw files, or commit messages.
- **Temp cleanup:** Always delete the temp database copy after extraction.
- **Expiry-aware:** Filter out expired cookies at query time.

## Platform

macOS only. Firefox profile path: `~/Library/Application Support/Firefox/Profiles/`.

For Linux, the path would be `~/.mozilla/firefox/` — not currently supported but straightforward to add.

## Dependencies

- **sqlite3** — pre-installed on macOS
- **Firefox** — must be installed with cookies for the target domain
