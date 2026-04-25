---
name: og-image-dynamic
description: Generate per-URL Open Graph images at runtime so every shared link unfurls with a distinct, branded preview card. Supports Cloudflare Workers (Satori), Vercel Edge (@vercel/og), and TanStack Start static builds. Use after shipping any app that gets shared on X/Reddit/LinkedIn/WhatsApp.
category: quality-review
argument-hint: [--runtime cf|vercel|node] [--route /api/og] [--template <file>] [--test]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:image
  - platform:agnostic
  - role:adapter
---

# OG Image Dynamic

Every share needs a preview card. A single static `og-image.png` for all URLs looks lazy and tanks click-through on Twitter/Reddit/LinkedIn previews. This skill wires up a `/api/og.png` endpoint that renders a per-URL, per-content image in <100ms and caches it at the edge.

## Usage

```
/ro:og-image-dynamic                              # auto-detect runtime, wire default template
/ro:og-image-dynamic --runtime cf                 # Cloudflare Workers (Satori + resvg)
/ro:og-image-dynamic --runtime vercel             # Vercel Edge (@vercel/og)
/ro:og-image-dynamic --route /api/og              # custom route path
/ro:og-image-dynamic --test                       # open the endpoint with sample params
```

## What gets wired

1. A server route (e.g. `src/routes/api/og.$slug.ts` or `/api/og.png`) that accepts query params and returns `image/png`.
2. A JSX-like template function that composes the card (title, subtitle, logo, accent colour).
3. Meta-tag updates in `src/routes/__root.tsx` (or the page-level route) so each route gets its own OG image URL.
4. Edge-cache headers (`Cache-Control: public, max-age=86400, s-maxage=604800`).

## Cloudflare Workers (preferred for TanStack Start on CF)

`@vercel/og` pulls in `@resvg/resvg-wasm` which runs fine on Workers, but the lighter-weight approach uses `satori` + `@resvg/resvg-wasm` directly:

```bash
pnpm add satori @resvg/resvg-wasm
```

Route:

```ts
// src/routes/api/og.ts
import { createFileRoute } from '@tanstack/react-router'
import satori from 'satori'
import { Resvg } from '@resvg/resvg-wasm'

// Load a font and the wasm binary once (module-level); Workers isolates reuse them.
// Put Inter-Regular.woff and resvg.wasm in src/assets/ and import with `?url` or inline.

export const Route = createFileRoute('/api/og')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { searchParams } = new URL(request.url)
        const title = searchParams.get('title') ?? 'Default title'
        const subtitle = searchParams.get('subtitle') ?? ''

        const svg = await satori(
          {
            type: 'div',
            props: {
              style: {
                display: 'flex',
                flexDirection: 'column',
                width: '1200px',
                height: '630px',
                padding: '80px',
                background: 'linear-gradient(135deg, #0f172a 0%, #1e3a8a 100%)',
                color: 'white',
                fontFamily: 'Inter',
              },
              children: [
                {
                  type: 'div',
                  props: {
                    style: { fontSize: 72, fontWeight: 700, lineHeight: 1.1 },
                    children: title,
                  },
                },
                subtitle && {
                  type: 'div',
                  props: {
                    style: { fontSize: 36, marginTop: 24, opacity: 0.8 },
                    children: subtitle,
                  },
                },
              ].filter(Boolean),
            },
          },
          {
            width: 1200,
            height: 630,
            fonts: [{ name: 'Inter', data: INTER_FONT, weight: 700, style: 'normal' }],
          },
        )

        const png = new Resvg(svg).render().asPng()

        return new Response(png, {
          headers: {
            'Content-Type': 'image/png',
            'Cache-Control': 'public, max-age=86400, s-maxage=604800, immutable',
          },
        })
      },
    },
  },
})
```

**Font loading:** satori requires a font binary passed as `ArrayBuffer`. On Workers, bundle via Vite:

```ts
import InterRegular from '@/assets/Inter-Regular.woff?url'
const INTER_FONT = await fetch(new URL(InterRegular, import.meta.url)).then((r) => r.arrayBuffer())
```

**Wasm loading:** `@resvg/resvg-wasm` needs explicit init on Workers. Follow their README's `initWasm()` step at module load.

## Vercel Edge

Simpler — `@vercel/og` ships everything:

```bash
pnpm add @vercel/og
```

```ts
// app/api/og/route.tsx
import { ImageResponse } from '@vercel/og'

export const runtime = 'edge'

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const title = searchParams.get('title') ?? 'Default title'

  return new ImageResponse(
    (
      <div style={{ display: 'flex', fontSize: 72, color: 'white', background: '#0f172a', width: '100%', height: '100%', padding: 80 }}>
        {title}
      </div>
    ),
    { width: 1200, height: 630 },
  )
}
```

## Meta-tag wiring (per-route)

In TanStack Start, set per-route meta in the file-based route:

```ts
// src/routes/posts/$slug.tsx
export const Route = createFileRoute('/posts/$slug')({
  loader: async ({ params }) => fetchPost(params.slug),
  head: ({ loaderData }) => ({
    meta: [
      { property: 'og:title', content: loaderData.title },
      { property: 'og:image', content: `/api/og?title=${encodeURIComponent(loaderData.title)}` },
      { name: 'twitter:card', content: 'summary_large_image' },
      { name: 'twitter:image', content: `/api/og?title=${encodeURIComponent(loaderData.title)}` },
    ],
  }),
})
```

## Testing the endpoint

```bash
# Local dev
curl -sL 'http://localhost:3000/api/og?title=Hello&subtitle=World' -o /tmp/og.png && open /tmp/og.png

# Production unfurl — real test uses platform debuggers:
# - Twitter/X: https://cards-dev.twitter.com/validator
# - Facebook/Meta: https://developers.facebook.com/tools/debug/
# - LinkedIn: https://www.linkedin.com/post-inspector/
# - Discord unfurls on paste into any channel.
```

Always verify on the actual platform. OG unfurl caches are aggressive (LinkedIn 7+ days); if the preview looks stale, add a cache-buster `?v=2` to the final URL.

## Template best practices

- **Size:** 1200×630 is the universal safe size. Twitter/X also accepts 1200×1200 (square). Pick one and standardise.
- **Text:** max ~60 chars title before it looks cramped. Use `title.slice(0, 80) + '…'` in the route.
- **Contrast:** WCAG AA minimum. Preview cards often show on white or black backgrounds, so internal contrast matters.
- **Logo corner:** bottom-right or bottom-left, 40-60px. Makes the card brandable without dominating.
- **No external fetches.** Embed fonts and logo as module imports. Runtime fetches to Google Fonts will slow the endpoint and risk failure.

## Caching strategy

```
Cache-Control: public, max-age=86400, s-maxage=604800, immutable
```

- `max-age=86400` — browser caches 1 day.
- `s-maxage=604800` — Cloudflare / Vercel edge caches 1 week.
- `immutable` — tells caches never to revalidate (safe because any content change changes the URL via query params).

If using query params for dynamic content, **the URL is the cache key** — different params = different cached image. No need for a cache-invalidation strategy.

## Gotchas

- **Wasm cold-start:** first request after deploy may take 300-500ms. Warm-up the endpoint from the deploy workflow.
- **Font subsetting:** a full Inter woff is ~400kb. Subset to just Latin characters if file size matters. Use `glyphhanger` or pre-subset with fontTools.
- **Wrong image on X:** X uses `twitter:image`, not `og:image`. Set both.
- **Discord preview latency:** Discord caches previews for ~1 hour. Testing repeatedly on the same URL will show stale. Use `?v=N` during dev.
- **Rate limits:** an unrestricted OG endpoint is an abuse vector. Add IP-based rate limiting (Cloudflare Workers: use `ratelimit` binding; Vercel: use `@upstash/ratelimit`).

## See also

- `/ro:posthog` — track which OG-image URLs actually get shared (`share` events with `item_id`)
- `/ro:seo-launch-ready` — complementary meta-tag + sitemap setup
- `/ro:cf-ship` / `/ro:fly-deploy` — deploy targets where this runs
- `/ro:app-polish` — umbrella skill that invokes this as check #3
