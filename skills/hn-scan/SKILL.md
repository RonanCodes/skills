---
name: hn-scan
description: Scan Hacker News for trends, hot threads, or specific topics. Returns findings — titles, points, comment highlights, URLs — without writing anywhere. Use when you want to see what's trending, research a topic, or pull a specific thread. Sibling to llm-wiki/ingest-hackernews (that one persists to a vault; this one just returns findings).
category: research
argument-hint: <query | hn-url | "frontpage" | "show" | "ask"> [--limit N] [--since 24h|7d|30d]
allowed-tools: Bash(curl *) Read
content-pipeline:
  - pipeline:scan
  - platform:agnostic
  - role:scanner
---

# HN Scan

Pull threads or topic results from Hacker News and return the distilled findings to the caller. No vault, no file writes — just a summary the caller can use.

## Usage

```
/ro:hn-scan "agent observability"              # search front page + recent
/ro:hn-scan "show hn AI agent" --since 30d     # search Show HN in last 30 days
/ro:hn-scan https://news.ycombinator.com/item?id=47799856   # fetch one thread
/ro:hn-scan frontpage --limit 30               # top N current front-page stories
/ro:hn-scan show --since 7d                    # Show HN in last week
/ro:hn-scan ask --since 7d                     # Ask HN in last week
```

## Modes

### 1. Topic search (free-text query)

Algolia HN search — no auth, no rate limit in practice.

```bash
curl -s "https://hn.algolia.com/api/v1/search?query=<encoded-query>&tags=story&hitsPerPage=30"
# Add &numericFilters=created_at_i>$(date -v-7d +%s) for --since 7d
```

For each hit return:
- `title`, `points`, `num_comments`, `author`, `url` (external link), `story_id`, `created_at`
- HN link: `https://news.ycombinator.com/item?id={story_id}`

Rank by points × recency (`points / (age_hours + 2)^1.8`).

### 2. URL mode (single thread)

If the arg is a HN URL or bare item id, fetch the full tree:

```bash
curl -s "https://hn.algolia.com/api/v1/items/{id}"
```

Return:
- Post metadata (title, points, author, date, linked URL)
- Top 10 comments by score (flatten, strip HTML to plain text, truncate to ~400 chars each)
- Total comment count

### 3. Frontpage / Show / Ask modes

```bash
# frontpage
curl -s "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30"
# Show HN
curl -s "https://hn.algolia.com/api/v1/search_by_date?tags=show_hn&hitsPerPage=30"
# Ask HN
curl -s "https://hn.algolia.com/api/v1/search_by_date?tags=ask_hn&hitsPerPage=30"
```

## Output format

Return a terse report the caller can reason over. No markdown files, no YAML frontmatter.

```
# HN scan: "<query>"  (<N> results, last <window>)

1. [<points>pts, <comments>c] <title>
   <external-url-if-any>
   https://news.ycombinator.com/item?id=<id>
   <1-line takeaway if comment count > 50 and the story is relevant>

2. ...
```

For single-thread mode include the top-comments summary under the header.

## HTML cleanup

Algolia returns HTML-encoded text. Before returning, convert:
- `<p>` → double newline
- `<a href="X">Y</a>` → `[Y](X)`
- `<code>` / `<pre>` → backticks / fences
- Common entities (`&#x27;`, `&amp;`, `&gt;`, `&lt;`, `&quot;`) → literal chars
- Strip any remaining tags

## Dependencies

None — uses `curl` + the free Algolia HN API.

## See also

- `llm-wiki/.claude/skills/ingest-hackernews` — the sibling skill that persists full threads into an Obsidian-style vault. Use that when you want to *keep* the content long-term; use `/ro:hn-scan` when you just want to see what's there.
- `/ro:trend-scan` — orchestrator that runs hn-scan + x-scan + linkedin-scan + reddit-scan in parallel for a topic.
- `/ro:x-scan`, `/ro:linkedin-scan`, `/ro:reddit-scan` — siblings for other sources.
