---
name: typefully-draft
description: Draft and queue social posts via the Typefully v2 API across X, LinkedIn, Threads, Bluesky, Mastodon, and any other connected account in a Typefully social set. Creates a draft you review in the Typefully app/web before it auto-posts, optionally schedules to a specific time, queues into the next free slot, returns a shareable preview link, or scopes to specific platforms via --targets. Supports single posts and threads. Reads TYPEFULLY_API_KEY and TYPEFULLY_SOCIAL_SET_ID from ~/.claude/.env. Use when user wants to schedule, queue, draft, or cross-post to any Typefully-connected platform.
category: marketing
argument-hint: <text> [--thread] [--schedule <iso>] [--queue-next] [--share] [--targets <list>]
allowed-tools: Bash(bash *) Bash(curl *) Bash(jq *) Bash(python3 *) Bash(set *) Bash(unset *) Bash(source *) Read
---

# Typefully Draft

Draft a post into Typefully so it stays in your review loop before it goes live. Threads, scheduling, shareable preview links, and per-platform targeting are first-class. Posts never bypass the Typefully approval gate, which keeps connected accounts (e.g. `@ronancodes`) clear of bot-flag risk.

This skill wraps the Typefully **v2** API. Drafts are scoped to a **social set** — a collection of connected platform accounts (X, LinkedIn, Threads, Bluesky, Mastodon). One draft can target one platform or all of them.

## Usage

```bash
# Single post, all four platforms (default targets: x,linkedin,threads,bluesky)
/ro:typefully-draft "shipped a 16:9 promo for connectionshelper.app today. PH next month."

# Single post, scheduled for a specific time (UTC)
/ro:typefully-draft "good morning EU" --schedule "2026-04-26T07:00:00Z"

# Queue into the social set's next free slot
/ro:typefully-draft "build-in-public day 3: shipped k6 load tests" --queue-next

# Thread on X + Bluesky only
/ro:typefully-draft --thread "Day 1 of launching connectionshelper.app.\n---\nThe stack: TanStack Start, Cloudflare Workers, D1, Drizzle.\n---\nWhat I'm watching this week: r/NYTConnections." --targets x,bluesky

# Get a shareable preview URL (for showing a friend before approval)
/ro:typefully-draft "thinking about a new tagline" --share

# LinkedIn-only post (different rhythm than X; don't blanket cross-post)
/ro:typefully-draft "engineering deep-dive on D1 caching" --targets linkedin
```

## Prerequisites

- **Typefully account** at <https://typefully.com>. Free plan supports the API.
- **API key** from Typefully → Settings → API → New API Key.
- **Social set ID** (the group of connected accounts) — find it via:

  ```bash
  curl -H "Authorization: Bearer $TYPEFULLY_API_KEY" \
    https://api.typefully.com/v2/social-sets | jq
  ```

- Add both to `~/.claude/.env`:

  ```
  # Typefully
  TYPEFULLY_API_KEY=<your-key>
  TYPEFULLY_SOCIAL_SET_ID=<numeric-id>
  ```

- `curl`, `jq`, and `python3` (all standard on macOS).

## Auth header

Typefully v2 uses the standard bearer-token format:

```
Authorization: Bearer <your-key>
```

(Earlier v1 used `X-API-Key`; that version is no longer the recommended path.)

## What this skill does NOT do

- **Doesn't write the post for you.** Compose the text in conversation; this skill is the queue mechanism. Voice rules live in `/ro:write-copy`.
- **Doesn't post directly to any platform.** Everything routes through Typefully so you stay in the approval loop. If you want direct X API posting (no third-party in the loop), build a separate skill against `POST /2/tweets` — that path has bot-flag risk on a personal-brand account and requires a Twitter Developer app. Same calculus for LinkedIn (their OAuth posts API) or Bluesky (the AT Protocol).
- **Doesn't auto-publish.** Default is "draft only." Add `--schedule` or `--queue-next` to schedule, but you should still eyeball in the Typefully app before the scheduled time hits.
- **Doesn't handle media uploads (yet).** Typefully v2 has `POST /v2/social-sets/{id}/media/upload`; that's a future addition.

## Process

### 1. Verify creds

```bash
set -a && source ~/.claude/.env && set +a
[ -n "$TYPEFULLY_API_KEY" ] && [ -n "$TYPEFULLY_SOCIAL_SET_ID" ] || {
  echo "Missing TYPEFULLY_API_KEY or TYPEFULLY_SOCIAL_SET_ID in ~/.claude/.env" >&2
  exit 1
}
```

### 2. Build the v2 payload

The wrapper script handles this. Schema:

```json
{
  "platforms": {
    "x":        { "enabled": true, "posts": [{ "text": "..." }] },
    "linkedin": { "enabled": true, "posts": [{ "text": "..." }] },
    "threads":  { "enabled": true, "posts": [{ "text": "..." }] },
    "bluesky":  { "enabled": true, "posts": [{ "text": "..." }] }
  },
  "publish_at": "2026-04-26T09:00:00Z",
  "share": false
}
```

Threading: `posts` is an array. The script splits the input on `\n---\n` (a clearer human marker than four-newlines) and emits one `{ "text": ... }` per part.

Optional fields:

| Field | Use |
|---|---|
| `publish_at` | ISO 8601 UTC, or `"now"`, or `"next-free-slot"` for queued posting |
| `share` | `true` to receive a public preview URL in the response |

### 3. POST to the social set's drafts endpoint

```bash
curl -sS -X POST "https://api.typefully.com/v2/social-sets/${TYPEFULLY_SOCIAL_SET_ID}/drafts" \
  -H "Authorization: Bearer $TYPEFULLY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload" | jq
```

### 4. Read the response

The response includes `id`, `private_url`, `share_url` (if `share=true`), and per-platform `*_published_url` fields once published. Open `https://typefully.com/?d=<id>` to review and approve.

## The wrapper script

`scripts/draft.sh` is the entry point invoked by the slash command.

```bash
bash scripts/draft.sh "<text>"                                       # all 4 platforms
bash scripts/draft.sh "<text>" --targets x                           # X only
bash scripts/draft.sh --thread "p1\n---\np2\n---\np3" --targets x    # X-only thread
bash scripts/draft.sh "<text>" --schedule "2026-04-26T09:00:00Z"
bash scripts/draft.sh "<text>" --queue-next
bash scripts/draft.sh "<text>" --share
```

## Per-platform targeting

`--targets` controls which `platforms.<name>.enabled` flags get flipped to `true`. Without `--targets` the default is `x,linkedin,threads,bluesky` (all four flipped on).

If you target a platform that isn't connected to your social set, the API returns 400. Connect the platform in Typefully first or scope `--targets` to the ones you have.

## Voice rules (when drafting in conversation)

When Claude composes the post text inside the conversation, load `/ro:write-copy` first. The rules that bite hardest on social:

- **No em-dashes (—) or en-dashes (–).** Use commas, colons, parentheses, full stops.
- **No AI-tells:** delve, leverage, robust, seamless, unlock, streamline, "in today's fast-paced world", "at the intersection of."
- **Hooks do work in the first 7 words.** Social feeds cut off fast; bury nothing.
- **Threads:** keep each post ≤ 250 chars to leave room for retweet quoting. Don't pad to 280.
- **Build-in-public posts:** lead with the specific (a number, a screenshot reference, a concrete fix). Skip the meta-narration.
- **No call-to-action stuffing.** One CTA per post, last line, or skip.

## Anti-patterns

- **Posting bypassing the Typefully review gate** (e.g. via direct platform APIs in this skill). The whole point of the third-party scheduler is the human-in-the-loop check on a personal brand account.
- **Auto-scheduling without `--schedule` or `--queue-next`.** Default is "draft only"; user should approve in the Typefully UI before publish.
- **Threads of more than 5 posts.** Most feeds punish long threads now; if the content needs more, write a blog post and link it.
- **Using `--share` with `--schedule`.** Pick one: a preview link is for "show a friend, then I'll publish manually"; a schedule is for "publish at this time, no further intervention." Combining them implies a workflow that doesn't exist.
- **Cross-posting identical copy to all four platforms blindly.** LinkedIn rewards different rhythm and length than X; Bluesky has a different culture than Threads. Use `--targets` to scope a draft to one platform when the voice doesn't translate.

## See also

- `/ro:write-copy` — voice rules (em-dashes, AI-tells, scroll-stop hooks)
- `/ro:x-scan` — read-only X scraper for trend / competitor research
- `/ro:linkedin-scan` — read-only LinkedIn scraper for competitor analysis
- `/ro:trend-scan` — find what's trending before drafting
- [Typefully v2 API docs](https://typefully.com/docs/api)
