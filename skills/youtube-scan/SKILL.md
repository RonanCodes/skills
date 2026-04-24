---
name: youtube-scan
description: Scan YouTube for videos by topic (search), channel (uploads feed), or URL (metadata). Returns titles, view counts, channel, upload date. Optionally auto-inlines a trimmed transcript snippet for high-signal hits via `--rich auto`. Pair with `/ro:video-summarize` for a full deep dive.
category: research
argument-hint: <topic-or-url-or-channel> [--since 24h|7d|30d] [--limit N] [--min-views N] [--rich auto|all|off] [--rich-threshold N] [--rich-keywords a,b,c]
allowed-tools: Bash(yt-dlp *) Bash(curl *) Bash(which *) Bash(date *) Bash(python3 *) Bash(grep *) Bash(head *) Bash(tr *) Read
---

# YouTube Scan

Three modes, auto-detected from the argument:

- **Topic search** — `"AI agents"` or `"MCP servers"` → `yt-dlp "ytsearchN:<q>"`
- **Channel feed** — `https://www.youtube.com/@<handle>` or channel URL → uploads RSS
- **Video URL** — `https://www.youtube.com/watch?v=...` or `https://youtu.be/...` → single-video metadata

By default, no transcripts — this is discovery, not digestion. With `--rich auto`, the skill pulls a trimmed transcript snippet for the subset of hits that match a "this might be load-bearing" heuristic (see below). For full transcript + slides + LLM summary, pipe a picked URL into `/ro:video-summarize`.

## Usage

```
/ro:youtube-scan "AI agents"                      # topic search, last 7d, top 15 by views
/ro:youtube-scan "MCP servers" --since 24h        # fresh drops
/ro:youtube-scan "vibe coding" --limit 30 --min-views 10000
/ro:youtube-scan https://www.youtube.com/@simonwillison        # channel's latest
/ro:youtube-scan https://www.youtube.com/watch?v=XXXX          # single video metadata
/ro:youtube-scan "MCP" --rich auto                # inline transcripts for high-signal hits
/ro:youtube-scan https://youtu.be/XXXX --rich all # force transcript on a single video
```

## Defaults

- **Window:** `7d`
- **Limit:** `15`
- **Min views:** none (raise with `--min-views` to filter out low-signal uploads)
- **Rich mode:** `off` (transcripts not fetched)
- **Rich threshold:** `50000` views (when `--rich auto`)
- **Rich keywords:** `mcp,agent,claude,anthropic,openai,protocol,spec,sdk` (when `--rich auto`)

## Mode: Topic search

```bash
yt-dlp "ytsearch${LIMIT}:${QUERY}" \
  --flat-playlist --dump-json \
  --match-filter "upload_date>=$(date -v-${SINCE} +%Y%m%d)" \
  2>/dev/null
```

Each JSON line has `title`, `url`, `channel`, `view_count`, `upload_date`, `duration`.

**Ranking heuristic:** `views / (days_since_upload + 2)` — similar to HN's age-decay, but view-weighted.

## Mode: Channel feed

Prefer the free RSS endpoint over `yt-dlp` for channel listings — no auth, no rate limiting:

```bash
# If given an @handle, first resolve to channel_id via yt-dlp
CHANNEL_ID=$(yt-dlp --print channel_id "$URL" --playlist-items 0 2>/dev/null | head -1)
curl -s "https://www.youtube.com/feeds/videos.xml?channel_id=${CHANNEL_ID}"
```

Atom XML. Parse with Python (namespace `http://www.w3.org/2005/Atom` and `http://search.yahoo.com/mrss/` for media metadata). Each `<entry>` has `<title>`, `<link href="...">`, `<published>`, `<media:statistics views="...">`.

## Mode: Single video URL

```bash
yt-dlp --dump-json --no-download "$URL"
```

Returns the full metadata blob. Pull: `title`, `uploader`, `view_count`, `like_count`, `upload_date`, `duration`, `description`, `tags`.

## Rich mode — inline transcript snippets

Lightweight transcript-grab for the subset of hits likely to contain novel content. Does NOT run any LLM — it just pulls captions and trims. This closes the "I only saw the title, missed the substance" gap for high-signal talks (conference keynotes, announcements, explainers from authoritative authors).

### Trigger heuristic (`--rich auto`)

A video gets a transcript snippet if **any** of:

1. `view_count >= ${RICH_THRESHOLD:-50000}` within the scan window, OR
2. Title (case-insensitive) contains any of `${RICH_KEYWORDS:-mcp,agent,claude,anthropic,openai,protocol,spec,sdk}`

Override per-call with `--rich-threshold N` and `--rich-keywords "a,b,c"`. For force-on-all, use `--rich all`; for force-off, use `--rich off` (the default).

### Fetching captions

```bash
TMP=$(mktemp -d)
yt-dlp \
  --write-auto-sub --skip-download \
  --sub-lang en --sub-format vtt \
  -o "$TMP/cap" \
  "$URL" 2>/dev/null
```

If no English auto-subs exist, skip gracefully (leave the entry title-only, flag `[no captions]`).

### VTT → plain text → trim

```bash
python3 - "$TMP/cap.en.vtt" <<'PY'
import sys, re, pathlib
vtt = pathlib.Path(sys.argv[1]).read_text(errors="ignore")
# drop WEBVTT header + cue timing lines, keep only caption text
lines = [l for l in vtt.splitlines()
         if l.strip() and "-->" not in l and not l.startswith(("WEBVTT", "Kind:", "Language:", "NOTE"))]
# strip HTML-like tags that yt-dlp injects (<c>, <00:00:00.000>)
text = re.sub(r"<[^>]+>", "", "\n".join(lines))
# deduplicate consecutive duplicate lines (auto-caption rolling overlap)
out, prev = [], None
for l in text.splitlines():
    s = l.strip()
    if s and s != prev:
        out.append(s); prev = s
joined = " ".join(out)
# trim to ~1000 words (first-1000 covers intro/thesis for most talks)
words = joined.split()
print(" ".join(words[:1000]))
PY
```

Output: ~1000 words of readable text. For a 30-min talk that's the intro + first third, which typically contains the thesis and any novel terminology.

### Output format with rich snippet

Under a triggered video, add a `> ` block with the snippet plus a marker so downstream consumers can tell it was auto-triggered:

```
1. <Title>  (<N> views · <M> days ago · <channel>)
   https://www.youtube.com/watch?v=<id>
   <brief gist from description, 1 line>

   📜 [transcript snippet, auto-rich, ~1000 words]
   > <snippet text...>
```

For videos that DON'T trigger, output is unchanged. Keep the scan lean.

### When to skip even if triggered

- Video duration > 120 minutes — probably a stream, too diffuse; the first 1000 words rarely capture a thesis
- No English auto-captions available
- Captions fetch errors (geo-blocks, rate limits)

In each case, append `[transcript skipped: <reason>]` to the entry and move on.

## Output

```
# YouTube: "<query>"  (window: <since>, mode: <search|channel|url>)

1. <Title>  (<N> views · <M> days ago · <channel>)
   https://www.youtube.com/watch?v=<id>
   <brief gist from description, 1 line>

2. ...
```

For the single-URL mode, emit:

```
# Video: <title>
Channel:  <channel>
Uploaded: <date> (<N days ago>)
Views:    <count>
Likes:    <count>
Duration: <mm:ss>

<description, first 5 lines>
```

## Discover mode (for trend-scan)

When called by `/ro:trend-scan --discover`, there's no topic. In that case run a handful of broad seeds in sequence:

```
ytsearch15:AI
ytsearch15:coding
ytsearch15:new tool
```

Filter to last 7d, dedupe by URL, sort by view count. Return the top 20.

If the caller passed `--rich auto` through (trend-scan does this by default in discover mode), apply the rich heuristic to each of the top 20 and inline transcript snippets for the matches. Typical yield: 2-5 videos triggered per scan.

## Dependencies

- `yt-dlp` (from the `video-summarize` skill install, or `brew install yt-dlp`)
- `curl` (for channel RSS)

## Error handling

- **yt-dlp fails for search** — YouTube occasionally rotates its scraping defenses. Fall back to `--extractor-args "youtube:player_client=web"` or try `--no-check-formats`.
- **Channel feed returns 404** — the channel handle → ID resolution failed. Ask the user for the canonical channel URL.
- **Trending feed** (`youtube.com/feed/trending`) is **broken** as of 2026-04 (redirects to homepage). Don't rely on it for discover mode; use seed searches instead.
- **Rich mode caption fetch fails** for some videos — non-fatal; the entry stays in the scan with `[transcript skipped: <reason>]` appended. Never let one bad video block the rest.

## See also

- [`video-summarize`](../video-summarize/SKILL.md) — downstream: pick a video, get its transcript + slides + LLM summary.
- [`hn-scan`](../hn-scan/SKILL.md), [`reddit-scan`](../reddit-scan/SKILL.md), [`x-scan`](../x-scan/SKILL.md) — sibling source scanners.
- [`trend-scan`](../trend-scan/SKILL.md) — upstream: orchestrates all source scanners in parallel.
- [`llm-wiki/.claude/skills/ingest-youtube`](https://github.com/RonanCodes/llm-wiki/blob/main/.claude/skills/ingest-youtube/SKILL.md) — when you want to keep a video in a vault.
