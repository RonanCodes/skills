---
name: producthunt-scan
description: Scan Product Hunt's daily / weekly / all-time rankings via the public Atom feed. Returns product names, taglines, URLs, upvotes (when exposed). No auth required. Use for "what launched today?" or niche topic filtering.
category: research
argument-hint: [topic] [--since today|week|month] [--limit N] [--category <slug>]
allowed-tools: Bash(curl *) Bash(python3 *) Read
content-pipeline:
  - pipeline:scan
  - platform:agnostic
  - role:scanner
---

# Product Hunt Scan

Three modes:

- **Today feed** — default, no topic — 50 freshest launches
- **Topic filter** — filter today/week feed by keyword match on title or tagline
- **Category feed** — scope to a PH category (e.g. `tech`, `productivity`, `ai`)

Product Hunt's public Atom feed is `https://www.producthunt.com/feed` — returns the current top products, no auth, atom-XML format.

## Usage

```
/ro:producthunt-scan                                 # top 30 launches today
/ro:producthunt-scan "AI agent"                      # filter today's feed by keyword
/ro:producthunt-scan "markdown" --since week         # past week filtered
/ro:producthunt-scan --category ai --limit 50        # AI category, more items
```

## Defaults

- **Since:** `today`
- **Limit:** `30`
- **Category:** none (full feed)

## Endpoints

```bash
# Today / main feed
curl -s "https://www.producthunt.com/feed"

# Category-scoped (replace <slug>)
curl -s "https://www.producthunt.com/feed?category=<slug>"
```

Common category slugs: `tech`, `ai`, `productivity`, `design-tools`, `developer-tools`, `marketing`, `web3`, `e-commerce`.

## Parsing

The feed is **Atom** not RSS. Use Python's `xml.etree.ElementTree` with namespace `http://www.w3.org/2005/Atom`:

```python
import xml.etree.ElementTree as ET
ns = {'a': 'http://www.w3.org/2005/Atom'}
tree = ET.parse('/tmp/ph.xml')
for e in tree.getroot().findall('a:entry', ns):
    title = e.findtext('a:title', default='', namespaces=ns)
    link = e.find('a:link', ns).get('href')
    updated = e.findtext('a:updated', default='', namespaces=ns)
    summary = e.findtext('a:summary', default='', namespaces=ns)
    # id → product slug
    # author → posted by
```

**Note:** the public feed does NOT expose upvote counts. If you need upvotes, the product page itself has them in JSON-LD (scrape the product URL), or use the GraphQL API (requires auth token — out of scope).

## Topic filter

When a topic is given, fetch the feed and filter entries where `title` or `summary` matches the topic (case-insensitive substring). PH titles are often 1-2 words so be lenient — also match the product page content if the topic is broad.

For better matching, fetch each candidate product page and check the tagline + description:

```bash
curl -s "https://www.producthunt.com/products/<slug>" | \
  python3 -c "
import sys, re
html = sys.stdin.read()
# tagline is in <meta property='og:description'>
m = re.search(r'<meta property=\"og:description\" content=\"([^\"]+)\"', html)
print(m.group(1) if m else '')
"
```

Rate-limit yourself — don't hammer product pages. Cap at ~20 per scan.

## Output

```
# Product Hunt  (since: <today|week>, category: <all|slug>, filter: "<topic or none>")

1. **<Product name>** — <tagline / og:description>
   <https://www.producthunt.com/products/<slug>>
   Launched: <date>  |  Category: <inferred from URL path or description>

2. ...

## Themes
- <1-line pattern spotted across today's launches>
- <another>
```

## Discover mode (for trend-scan)

Called by `/ro:trend-scan --discover`. Pull the main feed for today, cluster by theme (keyword extraction on titles + summaries), return the top themes with 2+ product mentions.

## Error handling

- **Empty feed / parse error** — PH sometimes returns an HTML error page instead of XML. Check response is `application/atom+xml` before parsing.
- **Topic yields zero results** — widen to week window (`--since week`) automatically and note the fallback.
- **Product page scrape blocked** — PH throttles aggressive scraping. Back off to 1 req/2s; if still blocked, skip the per-product enrichment.

## See also

- [`hn-scan`](../hn-scan/SKILL.md), [`reddit-scan`](../reddit-scan/SKILL.md), [`x-scan`](../x-scan/SKILL.md), [`youtube-scan`](../youtube-scan/SKILL.md) — sibling source scanners.
- [`trend-scan`](../trend-scan/SKILL.md) — upstream orchestrator.
- Product Hunt's GraphQL API (<https://api.producthunt.com/v2/docs>) — if upvote counts matter, upgrade to authenticated calls.
