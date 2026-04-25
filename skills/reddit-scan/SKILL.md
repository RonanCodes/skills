---
name: reddit-scan
description: Scan Reddit for hot threads in a subreddit, topic search, or a single-thread fetch. Uses the public .json endpoint (no auth). Returns findings without vault persistence. Sibling to llm-wiki/ingest-reddit.
category: research
argument-hint: <reddit-url | r/subreddit | "search:topic"> [--limit N] [--sort hot|top|new] [--since day|week|month|year]
allowed-tools: Bash(curl *) Read
content-pipeline:
  - pipeline:scan
  - platform:reddit
  - role:scanner
---

# Reddit Scan

Pull threads from Reddit and return distilled findings. No file writes.

## Usage

```
/ro:reddit-scan https://www.reddit.com/r/LocalLLaMA/comments/xxx/yyy/   # single thread
/ro:reddit-scan r/LocalLLaMA --sort hot --limit 25                       # hot in subreddit
/ro:reddit-scan r/LocalLLaMA --sort top --since week                     # top of week
/ro:reddit-scan "search:agent observability" --limit 20                  # cross-subreddit search
```

## Modes

### 1. Single-thread mode (URL)

```bash
curl -sL -H "User-Agent: ronan-skills-scan/1.0" \
  "https://www.reddit.com/r/{subreddit}/comments/{id}/{slug}.json?sort=top&limit=500"
```

Response is `[post, comments]`:
- `[0].data.children[0].data` → post (`title`, `selftext`, `author`, `score`, `num_comments`, `created_utc`, `url`, `is_self`)
- `[1].data.children[]` → comment tree (each `.data` has `author`, `body`, `score`, `created_utc`, `replies`)

Return:
- Post header (title, score, author, link if external)
- Post body (selftext) trimmed to ~800 chars
- Top 10 comments by score, flattened, each trimmed to ~300 chars
- Total comment count

Skip `kind === "more"` placeholders and `author === null` (deleted).

### 2. Subreddit listing mode (`r/<name>`)

```bash
# sort = hot | top | new | rising
curl -sL -H "User-Agent: ronan-skills-scan/1.0" \
  "https://www.reddit.com/r/{sub}/{sort}.json?limit={N}&t={since}"
```

`t` is one of `hour|day|week|month|year|all` (only relevant for `top`).

Return one line per thread with score, comment count, title, URL.

### 3. Search mode (`search:<topic>`)

```bash
curl -sL -H "User-Agent: ronan-skills-scan/1.0" \
  "https://www.reddit.com/search.json?q=<encoded>&sort=relevance&t={since}&limit={N}"
```

Same output shape as subreddit listing.

## Output format

```
# Reddit scan: <target>  (<N> results)

1. [<score>pts, <comments>c] <title>   r/<subreddit>
   <external-url if link post>
   https://www.reddit.com/<permalink>

2. ...
```

For single-thread mode: header + body + top comments section.

## Rate limiting + fallback

The public `.json` endpoint is lenient but not unlimited. On 429 or 403:
1. Wait ~3 seconds and retry once.
2. Swap `www.reddit.com` → `old.reddit.com` (same JSON shape, different CDN).
3. If still failing, report clearly — don't hammer.

Always send a descriptive User-Agent; Reddit blocks generic curl UAs more aggressively.

## Dependencies

None — `curl` only.

## See also

- `llm-wiki/.claude/skills/ingest-reddit` — persists full threads into a vault with YAML frontmatter. Use when you want the content kept.
- `/ro:trend-scan` — orchestrator running reddit-scan alongside the other source scanners.
- `/ro:hn-scan`, `/ro:x-scan`, `/ro:linkedin-scan` — siblings.
