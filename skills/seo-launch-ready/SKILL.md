---
name: seo-launch-ready
description: SEO groundwork for a freshly-shipped web app. Generates sitemap.xml, robots.txt, per-route canonical URLs, JSON-LD structured data, and a complete OG/Twitter meta set. Use right after `/ro:cf-ship` or `/ro:fly-deploy` as part of `/ro:app-polish` check #5.
category: quality-review
argument-hint: [--type <webapp|article|product|video>] [--domain <url>] [--sitemap-source <file>]
allowed-tools: Bash(*) Read Write Edit Glob Grep
content-pipeline:
  - pipeline:review
  - platform:agnostic
  - role:adapter
---

# SEO Launch Ready

Everything Google and social crawlers look for on day one. Getting the basics right at launch is cheap; retrofitting after indexing has stabilised is expensive.

## Usage

```
/ro:seo-launch-ready                                  # detect stack, full pass
/ro:seo-launch-ready --type article                   # article-shaped JSON-LD
/ro:seo-launch-ready --domain https://example.com     # set canonical origin
/ro:seo-launch-ready --sitemap-source puzzles.json    # build sitemap from data
```

## Step 0: Preflight (skip if already wired)

Before scaffolding anything, check what's already there. If all five core pieces exist, **stop and report "SEO already wired"** instead of dumping the recipe. The user can pass `--force` to re-scaffold.

```bash
test -f "$REPO/public/robots.txt" && echo "✓ robots.txt"
test -f "$REPO/public/sitemap.xml" || \
  find "$REPO/src/routes" -iname 'sitemap*.ts' -o -iname 'sitemap*.tsx' 2>/dev/null | grep -q . || \
  test -f "$REPO/app/sitemap.ts" && echo "✓ sitemap (static or dynamic)"
grep -qE "rel=\"canonical\"|rel: 'canonical'" "$REPO"/src/routes/__root.* 2>/dev/null && echo "✓ canonical link"
grep -qE "application/ld\+json" "$REPO"/src/routes/__root.* 2>/dev/null && echo "✓ JSON-LD"
grep -qE "og:title|property: 'og:title'" "$REPO"/src/routes/__root.* 2>/dev/null && echo "✓ OG meta"
```

Report each as ✓ / ✗. If 4+ of 5 are ✓, say "SEO already wired; nothing to scaffold. Audit: [list]. Use `--force` to re-scaffold or pick the missing piece by hand." Skip the rest of the steps.

If partially wired (1-3 of 5 ✓), tell the user which pieces exist and ask whether to fill the gaps or re-scaffold from scratch.

A common case worth calling out: a **dynamic sitemap route** (`src/routes/sitemap[.]xml.ts` for TanStack Start, `app/sitemap.ts` for Next.js App Router) is just as valid as a static `public/sitemap.xml`. Don't flag it as missing.

## What gets wired

1. **`public/robots.txt`** with sitemap URL.
2. **`public/sitemap.xml`** (static) or `src/routes/sitemap[.]xml.ts` (dynamic for data-driven sites).
3. **Canonical URL** meta in `src/routes/__root.tsx` + per-route overrides.
4. **JSON-LD structured data** (WebApplication / Article / Product / FAQ as appropriate).
5. **Full meta set:** title, description, og:title/description/image/url/type, twitter:card/image.
6. **Analytics cross-link:** only register with Google Search Console after the sitemap is live.

## 1. `robots.txt`

```
User-agent: *
Allow: /

# Block admin / draft routes
Disallow: /admin
Disallow: /_/

Sitemap: https://example.com/sitemap.xml
```

Put behind `public/robots.txt`. **Always include the absolute sitemap URL** — crawlers don't infer it.

## 2. Sitemap

### Static (marketing site, fixed routes)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://example.com/</loc><priority>1.0</priority></url>
  <url><loc>https://example.com/how-it-works</loc><priority>0.7</priority></url>
  <url><loc>https://example.com/pricing</loc><priority>0.9</priority></url>
</urlset>
```

### Dynamic (data-driven, e.g. one URL per puzzle, post, product)

TanStack Start route:

```ts
// src/routes/sitemap[.]xml.ts
import { createFileRoute } from '@tanstack/react-router'
import { db } from '@/lib/db'

export const Route = createFileRoute('/sitemap.xml')({
  server: {
    handlers: {
      GET: async () => {
        const puzzles = await db.query.puzzles.findMany({
          columns: { date: true },
          orderBy: (p, { desc }) => desc(p.date),
          limit: 365,
        })

        const urls = [
          { loc: 'https://example.com/', priority: 1.0 },
          { loc: 'https://example.com/how-it-works', priority: 0.7 },
          ...puzzles.map((p) => ({
            loc: `https://example.com/?date=${p.date}`,
            lastmod: p.date,
            priority: 0.8,
          })),
        ]

        const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls
  .map(
    (u) => `  <url>
    <loc>${u.loc}</loc>
    ${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}
    <priority>${u.priority}</priority>
  </url>`,
  )
  .join('\n')}
</urlset>`

        return new Response(xml, {
          headers: {
            'Content-Type': 'application/xml',
            'Cache-Control': 'public, max-age=3600, s-maxage=86400',
          },
        })
      },
    },
  },
})
```

**Cap at ~50k URLs per sitemap.** If you exceed it, switch to a sitemap index (`sitemap_index.xml`) listing sub-sitemaps.

## 3. Canonical URL

Per-route canonical prevents duplicate-content penalties (e.g. `?source=pwa` tracking suffix).

In `src/routes/__root.tsx`:

```tsx
head: () => ({
  links: [
    { rel: 'canonical', href: 'https://example.com' + location.pathname },
  ],
}),
```

For data-driven routes (`/posts/$slug`), override in the file-based route:

```tsx
head: ({ loaderData }) => ({
  links: [
    { rel: 'canonical', href: `https://example.com/posts/${loaderData.slug}` },
  ],
  meta: [...],
}),
```

## 4. JSON-LD structured data

Pick one primary schema per page type. Google supports many; pick the narrowest fit.

**Homepage — `WebApplication`** (good for tool-shaped apps):

```tsx
// src/routes/__root.tsx
scripts: [
  {
    type: 'application/ld+json',
    children: JSON.stringify({
      '@context': 'https://schema.org',
      '@type': 'WebApplication',
      name: 'Connections Helper',
      url: 'https://example.com',
      description: 'NYT Connections puzzle sidekick with hints and definitions.',
      applicationCategory: 'GameApplication',
      operatingSystem: 'Web',
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      author: { '@type': 'Person', name: 'Ronan Connolly', url: 'https://ronanconnolly.dev' },
    }),
  },
],
```

**Article page — `Article`:**

```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "The article title",
  "datePublished": "2026-04-20",
  "dateModified": "2026-04-21",
  "author": { "@type": "Person", "name": "Ronan Connolly" },
  "image": "https://example.com/og/article-slug.png"
}
```

**Product page — `Product`** (if selling anything):

```json
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Product name",
  "description": "...",
  "image": "...",
  "offers": { "@type": "Offer", "price": "29", "priceCurrency": "USD" }
}
```

**FAQ section — `FAQPage`** (/how-it-works, /pricing often qualify):

```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Is this free?",
      "acceptedAnswer": { "@type": "Answer", "text": "Yes, completely." }
    }
  ]
}
```

Rich results trigger on questions that exist as visible `h3`/`dt` in the page. Don't invent FAQs for the schema; it's a mismatch Google penalises.

## 5. Full meta set

Minimum viable for social + search:

```tsx
meta: [
  { title: 'Connections Helper — NYT puzzle sidekick' },
  { name: 'description', content: 'Hints and definitions for today\'s NYT Connections puzzle.' },

  // Open Graph
  { property: 'og:title', content: 'Connections Helper' },
  { property: 'og:description', content: 'Hints and definitions for today\'s NYT Connections.' },
  { property: 'og:image', content: 'https://example.com/api/og?title=Connections+Helper' },
  { property: 'og:url', content: 'https://example.com' },
  { property: 'og:type', content: 'website' },
  { property: 'og:site_name', content: 'Connections Helper' },

  // Twitter
  { name: 'twitter:card', content: 'summary_large_image' },
  { name: 'twitter:site', content: '@yourhandle' },
  { name: 'twitter:creator', content: '@yourhandle' },
  { name: 'twitter:title', content: 'Connections Helper' },
  { name: 'twitter:description', content: 'Hints and definitions for today\'s puzzle.' },
  { name: 'twitter:image', content: 'https://example.com/api/og?title=Connections+Helper' },
],
```

**Title length:** 50-60 characters before Google truncates. **Description:** 150-160 characters. **OG image:** 1200×630.

## 6. Per-route overrides

Each data-driven route should override title + description + OG image with route-specific values. Generic site-wide defaults on `/posts/$slug` is a missed opportunity:

```tsx
head: ({ loaderData }) => ({
  meta: [
    { title: `${loaderData.title} — Connections Helper` },
    { name: 'description', content: loaderData.excerpt ?? 'Default' },
    { property: 'og:title', content: loaderData.title },
    { property: 'og:image', content: `/api/og?title=${encodeURIComponent(loaderData.title)}` },
    { name: 'twitter:image', content: `/api/og?title=${encodeURIComponent(loaderData.title)}` },
  ],
}),
```

Pairs with `/ro:og-image-dynamic`.

## Verifying

```bash
# Local
curl -sL https://example.com/robots.txt
curl -sL https://example.com/sitemap.xml | head -40

# Structured data
# Google Rich Results Test: https://search.google.com/test/rich-results
# Schema.org validator: https://validator.schema.org/

# Meta tags
# OG debugger: https://developers.facebook.com/tools/debug/
# Twitter card validator: https://cards-dev.twitter.com/validator
# LinkedIn post inspector: https://www.linkedin.com/post-inspector/
```

**Submit to Search Console after the sitemap is live.** Add the `sitemap.xml` URL; indexing usually starts within 24-48h.

## Gotchas

- **Don't redirect `/` to `/en` or similar on initial load.** Crawlers follow 301s fine but lose internal link equity each hop.
- **Prerender or SSR matters for indexing.** Client-only SPAs index badly for content pages. TanStack Start SSR is fine; Vite SPA with no SSR is not.
- **JSON-LD must match visible content.** Schema about an author that isn't listed on the page triggers a structured-data warning.
- **Sitemap should only list canonical URLs.** Don't include redirects, `?utm=` variants, or admin routes.
- **`robots.txt` path is fixed.** `/robots.txt`, not `/meta/robots.txt`. Same for sitemap, unless you list it in `robots.txt`.
- **`noindex` on staging.** Add `<meta name="robots" content="noindex">` conditional on `import.meta.env.PROD === false` or a staging hostname check. A staged leak can take weeks to de-index.

## Adjacent moves worth doing same-day

- **Google Search Console** + **Bing Webmaster Tools** — verify via DNS TXT.
- **Analytics goals tied to search traffic:** `utm_source=google` / `referrer: google.com` segments in PostHog (`/ro:posthog`).
- **Backlink seed:** submit to 2-3 niche directories (Product Hunt, IndieHackers, StartupList) within week 1.
- **One evergreen piece of written content** at a stable URL that targets an exact-match query people search (e.g. `/guides/nyt-connections-strategy`).

## When NOT to bother

- Staging / preview environments. `noindex` them and move on.
- Personal dashboards that require auth. Nothing to index.
- Apps behind paywalls — Google won't index the content anyway; SEO is for the marketing surface, not the app.

## See also

- `/ro:og-image-dynamic` — per-URL OG images referenced in the meta block
- `/ro:app-polish` — umbrella; this is check #5
- `/ro:posthog` — track search-referred traffic + conversion
- `/ro:cf-ship` / `/ro:fly-deploy` — where the deploy sets the canonical hostname
- Google Search Central: https://developers.google.com/search/docs
- Schema.org: https://schema.org/
