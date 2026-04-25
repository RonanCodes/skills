#!/usr/bin/env bash
# typefully-draft/scripts/draft.sh
#
# Wraps the Typefully v2 Drafts API. Drafts and queues posts across X,
# LinkedIn, Threads, Bluesky, and any other connected platform within a
# Typefully social set.
#
# Auth:     Authorization: Bearer <key>
# Endpoint: POST /v2/social-sets/{social_set_id}/drafts
#
# Reads from ~/.claude/.env:
#   TYPEFULLY_API_KEY         (required)
#   TYPEFULLY_SOCIAL_SET_ID   (required — find via GET /v2/social-sets)
#
# Threads use \n---\n as the inter-post separator in the input string.

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  draft.sh <text> [--thread] [--schedule <iso8601>] [--queue-next] [--share] [--targets <list>]

Options:
  --thread           Treat <text> as a thread; posts separated by literal "\n---\n".
                     Sent as a multi-post array to platforms that support threads.
  --schedule <iso>   Schedule for a specific UTC time, e.g. 2026-04-26T09:00:00Z.
                     Maps to v2 publish_at.
  --queue-next       Queue into the social set's next free slot (publish_at=next-free-slot).
  --share            Return a shareable preview URL in the response.
  --targets <list>   Comma-separated platform names to enable. Default: x,linkedin,threads,bluesky.
                     Only platforms connected to the social set will accept posts; others 400.

Examples:
  draft.sh "shipped a new feature today"                          # all 4 platforms
  draft.sh "engineering deep-dive" --targets linkedin             # LinkedIn only
  draft.sh --thread "p1\n---\np2\n---\np3" --targets x,bluesky    # X+Bluesky thread
  draft.sh "morning EU" --schedule "2026-04-26T07:00:00Z"
  draft.sh "PH launch day" --queue-next
USAGE
  exit 2
}

TEXT=""
IS_THREAD=0
SCHEDULE=""
QUEUE_NEXT=0
SHARE=0
TARGETS=""

while (("$#")); do
  case "$1" in
    --thread)        IS_THREAD=1; shift ;;
    --schedule)      SCHEDULE="${2:-}"; shift 2 ;;
    --queue-next)    QUEUE_NEXT=1; shift ;;
    --share)         SHARE=1; shift ;;
    --targets)       TARGETS="${2:-}"; shift 2 ;;
    -h|--help)       usage ;;
    --*)             echo "Unknown flag: $1" >&2; usage ;;
    *)
      if [ -z "$TEXT" ]; then
        TEXT="$1"
      else
        echo "Multiple positional args; pass thread parts as one string with \\n---\\n separators" >&2
        usage
      fi
      shift
      ;;
  esac
done

[ -n "$TEXT" ] || { echo "Missing <text>" >&2; usage; }

if [ -n "$SCHEDULE" ] && [ "$QUEUE_NEXT" -eq 1 ]; then
  echo "Use --schedule OR --queue-next, not both" >&2
  exit 2
fi
if [ "$SHARE" -eq 1 ] && { [ -n "$SCHEDULE" ] || [ "$QUEUE_NEXT" -eq 1 ]; }; then
  echo "--share is for preview-only drafts; combining with a schedule doesn't fit a real workflow" >&2
  exit 2
fi

# Load creds.
if [ -f "$HOME/.claude/.env" ]; then
  set -a; . "$HOME/.claude/.env"; set +a
fi
: "${TYPEFULLY_API_KEY:?Missing TYPEFULLY_API_KEY in ~/.claude/.env}"
: "${TYPEFULLY_SOCIAL_SET_ID:?Missing TYPEFULLY_SOCIAL_SET_ID in ~/.claude/.env. Find it via: curl -H \"Authorization: Bearer \$TYPEFULLY_API_KEY\" https://api.typefully.com/v2/social-sets}"

# Build the posts array. For threads, split on the literal "\n---\n" token
# (matches what the user typed, NOT actual newlines). For single posts, one entry.
if [ "$IS_THREAD" -eq 1 ]; then
  POSTS_JSON=$(
    printf '%s' "$TEXT" \
      | python3 -c 'import sys, json; parts=[p.strip() for p in sys.stdin.read().split("\\n---\\n") if p.strip()]; print(json.dumps([{"text": p} for p in parts]))'
  )
else
  POSTS_JSON=$(jq -n --arg t "$TEXT" '[{text: $t}]')
fi

# Resolve target platforms.
TARGETS_LIST="${TARGETS:-x,linkedin,threads,bluesky}"
PLATFORMS_JSON=$(
  printf '%s' "$TARGETS_LIST" \
    | tr ',' '\n' \
    | jq -R '.' \
    | jq -s --argjson posts "$POSTS_JSON" '
        reduce .[] as $p ({}; .[$p | gsub("\\s"; "")] = {enabled: true, posts: $posts})
      '
)

# Build the request body. v2 uses publish_at (ISO or "now"/"next-free-slot") and share (bool).
PUBLISH_AT=""
if [ -n "$SCHEDULE" ]; then
  PUBLISH_AT="$SCHEDULE"
elif [ "$QUEUE_NEXT" -eq 1 ]; then
  PUBLISH_AT="next-free-slot"
fi

PAYLOAD=$(jq -n \
  --argjson platforms "$PLATFORMS_JSON" \
  --arg publish_at "$PUBLISH_AT" \
  --argjson share "$SHARE" \
  '{ platforms: $platforms }
   + (if $publish_at != "" then { publish_at: $publish_at } else {} end)
   + (if $share == 1 then { share: true } else {} end)')

# POST to the social set's drafts endpoint.
URL="https://api.typefully.com/v2/social-sets/${TYPEFULLY_SOCIAL_SET_ID}/drafts"
RESPONSE=$(curl -sS -w '\n%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer $TYPEFULLY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Typefully API error (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq . >&2 2>/dev/null || echo "$BODY" >&2
  if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo >&2
    echo "Tip: regenerate the key at Typefully → Settings → API → New API Key," >&2
    echo "     then update TYPEFULLY_API_KEY in ~/.claude/.env." >&2
  fi
  exit 1
fi

# Pretty summary. v2 response shape: { id, share_url?, publish_at?, ... }.
ID=$(echo "$BODY" | jq -r '.id // empty')
SHARE_URL=$(echo "$BODY" | jq -r '.share_url // empty')
PUBLISH_AT_OUT=$(echo "$BODY" | jq -r '.publish_at // empty')

echo "Draft created."
[ -n "$ID" ]              && echo "  id:           $ID"
[ -n "$ID" ]              && echo "  review:       https://typefully.com/?d=$ID"
[ -n "$SHARE_URL" ]       && echo "  share:        $SHARE_URL"
[ -n "$PUBLISH_AT_OUT" ]  && echo "  publish_at:   $PUBLISH_AT_OUT"
echo
echo "Full response:"
echo "$BODY" | jq .
