---
name: trend-scan
description: Two modes — (1) discover what's trending right now across Hacker News, Reddit, YouTube, Product Hunt (no topic needed), returning a picklist of top N themes; (2) deep-dive a specific topic across the same sources and return a ranked brief. Flow: discover → user picks → deep-dive. YouTube hits matching a "load-bearing" heuristic get transcript snippets inlined by default.
category: research
argument-hint: [topic] [--discover] [--sources hn,reddit,youtube,producthunt,x,linkedin] [--since 24h|7d|30d] [--limit N] [--rich auto|all|off]
allowed-tools: Bash(curl *) Read
content-pipeline:
  - pipeline:scan
  - platform:multi
  - role:orchestrator
---

# Trend Scan

Parallel fan-out across source scanners. Two modes sharing the same plumbing:

- **Discover mode** (no topic arg, or `--discover`) — "what's hot right now?" Pulls each source's hot/front feeds, extracts themes, returns a numbered picklist so the caller can pick one.
- **Deep-dive mode** (topic arg given) — "tell me everything about X right now." Scans each source for that query, ranks, and synthesises.

The natural loop: `/ro:trend-scan` → pick a theme → `/ro:trend-scan "<theme>"`.

## Usage

```
# discover
/ro:trend-scan                                   # top 10 themes across hn/x/reddit, last 7d
/ro:trend-scan --discover --since 24h --limit 15 # fresher, more themes
/ro:trend-scan --discover --sources hn,reddit    # skip X if you know nitter's down

# deep-dive
/ro:trend-scan "agent observability"
/ro:trend-scan "MCP servers" --sources hn,reddit --since 7d
/ro:trend-scan "vibe coding" --since 30d --limit 15
```

## Defaults

- **Sources:** `hn,reddit,youtube,producthunt` (X and LinkedIn are opt-in — X because nitter mirrors are currently dead, LinkedIn because cookie auth is required)
- **Window:** `7d`
- **Limit:** 10 items per source in deep-dive; 10 themes total in discover
- **Rich mode:** `auto` for YouTube in discover mode (transcript snippets inlined for the ~2-5 high-signal hits per scan). Override with `--rich off` for a lean scan, or `--rich all` to transcript every YT hit (slow)

## Why rich mode matters

Without inline transcripts, trend-scan surfaces YouTube talks by title and view count only. A keynote like "The Future of MCP" is logged as a high-view hit; the actual substance (new concepts, timelines, quotes the user would want to act on) stays invisible until someone watches it. The auto-rich default closes that gap: for videos that match the trigger heuristic, ~1000 words of captions land inline in the scan output, so the caller (Claude or user) can react immediately.

Precedent: the "server cards" concept went untracked for 4 days in 2026-04 because its keynote was logged by title only. Since fixed.

## Mode: Discover

Use this when the caller hasn't named a topic yet.

1. **Fan out** — pull the most-recent/highest-engagement feed from each source:
   - HN: `/ro:hn-scan frontpage --limit 30` + `/ro:hn-scan show --since 7d --limit 15`
   - Reddit: hit 4–6 curated subs via `/ro:reddit-scan r/<sub> --sort top --since week --limit 10` each. Default sub set: `r/LocalLLaMA`, `r/ClaudeAI`, `r/singularity`, `r/programming`, `r/hackernews`, `r/OpenAI`
   - YouTube: `/ro:youtube-scan --rich auto` in discover mode — runs 3 seed searches (`AI`, `coding`, `new tool`), dedupe by URL, sort by views, and inlines transcript snippets for hits matching the rich heuristic (default: views ≥ 50k OR title contains mcp/agent/claude/anthropic/openai/protocol/spec/sdk)
   - Product Hunt: `/ro:producthunt-scan` — today's feed, cluster by theme keywords
   - X: `/ro:x-scan "search:AI"` (or a set of broad seeds) — be ready for nitter failure, skip cleanly
2. **Normalise** — same shape as deep-dive (see below).
3. **Extract themes** — cluster titles/gists into themes:
   - Extract ~3-word noun phrases from titles (e.g. "agent observability", "MCP servers", "prompt caching")
   - Group items sharing a linked URL or near-identical titles
   - Score each theme by Σ(item ranks) + cross-source bonus (appearing on 2+ sources = ×1.5)
4. **Return a picklist** with brief evidence per theme — never a single-item verdict. The caller picks.

### Discover output

```
# What's trending  (window: <since>, sources: <which ran>)

1. **<Theme>** (<N> mentions, sources: hn, x)
   - [HN, 700pts] <representative title>  https://news.ycombinator.com/item?id=<id>
   - [X, 4.2k♥] @<user>: <gist>            https://x.com/...
   <1-line gist of what the theme is actually about>

2. **<Theme>** ...

...

## Next step
Pick one with: `/ro:trend-scan "<theme>"` for a deep-dive.
```

## Mode: Deep-dive

Use this when the caller has named a topic.

1. **Fan out** — run the selected source scans in parallel. Each is an independent curl call, so they complete in roughly the time of the slowest one.
2. **Normalise** — for each result, capture:
   - `source` (`hn` | `x` | `reddit` | `linkedin`)
   - `title_or_gist` (headline, tweet text, or post summary)
   - `url` (the thread / post URL)
   - `score` (points, likes, upvotes — source-specific units)
   - `comments` (if applicable)
   - `author`
   - `created_at`
3. **Rank** — combine recency + engagement. Simple heuristic:
   - `rank = score / (age_hours + 2)^1.5`
   - Cap score per source (HN points scale differently from X likes) by computing per-source z-scores before blending, then sort across sources.
4. **Cluster (optional)** — if two items clearly reference the same thing (same linked URL, or near-identical titles), merge them into a single entry with `sources: [hn, x]`.
5. **Summarise** — surface the top N (default 15) across all sources, plus a short "themes" paragraph listing patterns you spot.

## Deep-dive output

```
# Trend: "<topic>"  (window: <since>, sources: <which ran>)

## Themes
- <one-line pattern #1>
- <one-line pattern #2>
- <one-line pattern #3>

## Top items

1. [HN, <points>pts, <comments>c] <title>
   https://news.ycombinator.com/item?id=<id>
   <external url if relevant>
   <1-line takeaway>

2. [X, <likes>♥] @<user>: <gist>
   https://x.com/<user>/status/<id>

3. [Reddit, <score>, r/<sub>] <title>
   https://reddit.com/<permalink>

...

## Sources that failed or were skipped
- LinkedIn: not requested (opt-in)
- X: no results (nitter mirrors down — retry later with `--sources hn,reddit`)
```

## Error handling

- **Partial failure is OK** — if X fails but HN + Reddit succeed, return what you have with a note under "Sources that failed".
- **Total failure** — if every source fails, explain why (rate limit, network) and suggest `/ro:perplexity-research` as a fallback.

## When to use which tool

| Task | Use |
|---|---|
| "What's hot right now?" (no topic) | `/ro:trend-scan` (discover mode) |
| "What's hot on this topic?" | `/ro:trend-scan "<topic>"` (deep-dive) |
| "Fetch this specific thread" | `/ro:hn-scan <url>` or `/ro:reddit-scan <url>` |
| "Read this tweet" | `/ro:x-scan <url>` |
| "Research a topic with citations" | `/ro:perplexity-research` |
| "Keep this content long-term" | `llm-wiki /ingest` |

## Dependencies

Inherits dependencies from the scanners it calls (`curl`, optional `firefox-cookies` for LinkedIn).

## See also

- `/ro:hn-scan`, `/ro:x-scan`, `/ro:reddit-scan`, `/ro:linkedin-scan` — the per-source skills this orchestrates.
- `/ro:perplexity-research` — citation-backed AI research; complementary (perplexity = depth, trend-scan = breadth).
- `llm-wiki/.claude/skills/ingest` — when you want to keep the findings.
