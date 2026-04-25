---
name: x-scan
description: Scan X (Twitter) for posts from a user, search results, or single-tweet fetches. Uses FXTwitter (no auth) for single tweets. Returns findings without vault persistence. Sibling to llm-wiki/ingest-tweet.
category: research
argument-hint: <tweet-url | @user | "search:topic"> [--limit N]
allowed-tools: Bash(curl *) Read
content-pipeline:
  - pipeline:scan
  - platform:x
  - role:scanner
---

# X Scan

Pull posts from X / Twitter and return distilled findings. No file writes.

## Usage

```
/ro:x-scan https://x.com/user/status/1234567890   # one tweet, full text
/ro:x-scan @karpathy --limit 20                   # recent posts by user
/ro:x-scan "search:agent observability"           # topic search
```

## Modes

### 1. Single-tweet mode (URL)

FXTwitter — free, no auth, returns full text including long "note tweets":

```bash
curl -s "https://api.fxtwitter.com/{user}/status/{id}"
```

Return: `tweet.text`, author (`name @screen_name`), `created_at`, `likes/retweets/replies`, quoted tweet if any, media URLs if any.

Strip `?s=46&t=...` tracking params from the input URL before parsing.

### 2. User timeline mode (`@user`)

**FXTwitter doesn't expose timelines without auth.** Options in order of preference:

1. Use Nitter mirror RSS if one is live — these go up and down; try a list and use the first that returns 200:
   - `https://nitter.net/{user}/rss`
   - `https://nitter.poast.org/{user}/rss`
   - `https://nitter.privacyredirect.com/{user}/rss`
2. Parse the RSS with `curl ... | xmllint --xpath '//item'` or a simple sed pipeline. Extract title (= tweet text preview), `pubDate`, and the tweet URL from `<link>`.
3. For each URL, `/ro:x-scan` can fall back to the single-tweet fetch if the caller wants full content.

If **all mirrors fail**, report that clearly and suggest the caller either paste specific tweet URLs or switch to `/ro:hn-scan` / `/ro:linkedin-scan`.

### 3. Search mode (`search:<topic>`)

Same Nitter fallback as above with `/search?q={encoded-topic}&f=tweets` — again, mirrors are flaky. If the caller has access to the paid X API, prefer that (check for `X_API_BEARER` env var and use `https://api.x.com/2/tweets/search/recent` if set).

## Output format

```
# X scan: <target>  (<N> results)

1. @<screen_name> (<likes>♥ <retweets>↻ · <time ago>)
   <tweet text, stripped of t.co links>
   https://x.com/<user>/status/<id>

2. ...
```

For single-tweet mode include the full text, not a truncation.

## Cookie-based auth (optional, for richer fetches)

If Nitter is all down AND the caller needs timeline/search, the `firefox-cookies` skill can extract X session cookies for authenticated scraping. This is brittle (layout-dependent) — only fall back to it when the free paths are exhausted and the caller has explicitly opted in.

## Dependencies

- `curl` — always
- `xmllint` (from `libxml2`) — for RSS parsing, optional
- `firefox-cookies` skill — optional last-resort fallback

## See also

- `llm-wiki/.claude/skills/ingest-tweet` — persists single tweets into a vault. Use when you want to keep a tweet long-term.
- `/ro:trend-scan` — orchestrator running x-scan alongside hn-scan, linkedin-scan, reddit-scan.
- `/ro:hn-scan`, `/ro:linkedin-scan`, `/ro:reddit-scan`.
