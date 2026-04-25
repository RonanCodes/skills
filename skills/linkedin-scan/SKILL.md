---
name: linkedin-scan
description: Scan LinkedIn posts for a URL or pasted content, or fetch recent posts by a person/company. Uses cookie auth via browser-cookies (Firefox/Brave/Chrome/Arc) when available, otherwise pasted-text fallback. Returns findings without vault persistence. Sibling to llm-wiki/ingest-linkedin.
category: research
argument-hint: <linkedin-url | "paste" | @person-slug> [--limit N]
allowed-tools: Bash(curl *) Read
content-pipeline:
  - pipeline:scan
  - platform:linkedin
  - role:scanner
---

# LinkedIn Scan

Pull LinkedIn post(s) and return distilled findings. No file writes.

LinkedIn is unfriendly to scrapers (auth wall, HTML churn, anti-bot). Expect pasted-text mode to be the most reliable path.

## Usage

```
/ro:linkedin-scan https://www.linkedin.com/posts/someone-activity-xxxx   # one post, cookie auth
/ro:linkedin-scan paste                                                    # caller will paste post text
/ro:linkedin-scan @satya-nadella --limit 10                                # recent posts by slug (cookie auth)
```

## Mode detection

- Arg starts with `http` → URL mode (cookie auth)
- Arg is `paste` or empty → prompt caller to paste the post, then parse
- Arg starts with `@` → profile feed mode (cookie auth)

## URL mode (cookie auth)

1. Get cookies for `linkedin.com` via the `browser-cookies` skill (falls back to `firefox-cookies` if browser-cookies isn't available)
2. Fetch:
   ```bash
   curl -sL \
     -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
     -H "$COOKIE_HEADER" \
     "<linkedin-url>"
   ```
3. Parse the HTML in this order (first that returns content wins):
   - JSON-LD block: `<script type="application/ld+json">...</script>` — look for `articleBody` / `text`
   - `feed-shared-update-v2__description` divs
   - `feed-shared-actor__name` span for author, `feed-shared-actor__sub-description` for headline
4. If auth fails (403, redirect to login, empty content): stop, tell the caller to `/ro:linkedin-scan paste` instead.

## Paste mode

Prompt:
> Paste the LinkedIn post text. Include the author name on the first line if possible. End with an empty line.

Parse the pasted content:
- First line (or clearly-a-name line) → author
- Remaining body → post text
- `#hashtags` → tags
- If the caller pastes a URL alongside, capture it as source

## Profile feed mode (`@slug`)

Same cookie-auth flow as URL mode, hitting `https://www.linkedin.com/in/{slug}/recent-activity/all/`. Parse the first N posts. Very brittle — LinkedIn's feed markup changes often. If it breaks, tell the caller to open the profile in Firefox and copy-paste the top few posts.

## Output format

```
# LinkedIn scan: <target>  (<N> results)

1. <Author Name> — <headline if known>  (<time ago>)
   <post text, trimmed to ~500 chars with "..." if truncated>
   Tags: #foo #bar
   <linkedin-url if derivable>

2. ...
```

Never echo back cookie values or session tokens in output.

## Dependencies

- `curl` — always
- `browser-cookies` skill — required for URL / profile-feed modes (or legacy `firefox-cookies` for Firefox-only setups)

## See also

- `llm-wiki/.claude/skills/ingest-linkedin` — persists LinkedIn posts into a vault with full YAML frontmatter and wiki source-notes. Use when you want to keep the content.
- `/ro:trend-scan` — orchestrator.
- `/ro:hn-scan`, `/ro:x-scan`, `/ro:reddit-scan` — other source scanners.
- `browser-cookies` — cookie extraction (current); `firefox-cookies` — legacy Firefox-only fallback.
- `/ro:linkedin` — write path (official API: posts + draft-mode edits).
- `/ro:linkedin-voyager` — ToS-grey read path via unofficial Voyager API (bio, experience, full profile).
