---
name: share-assets
description: From one source brand mark, generate the full set of identity + share assets (favicon, app icons, PWA manifest, static OG image, Twitter card, dynamic OG route, JSON-LD) and wire them into a TanStack Start app's head + public/. Use when starting a new app or when an existing app's link previews look broken on X / WhatsApp / iMessage / LinkedIn / Slack.
category: development
argument-hint: [--source <path-to-svg>] [--no-dynamic-og] [--brand-color <hex>] <app-name>
allowed-tools: Read Write Edit Glob Grep Bash AskUserQuestion
content-pipeline:
  - pipeline:image
  - platform:agnostic
  - role:adapter
---

# Share Assets

Builds out the brand-identity + social-share asset set every shipped app needs but every new repo forgets. One source SVG mark in, the full deliverable set out:

- `public/favicon.ico` (multi-resolution, 16/32/48)
- `public/favicon.svg` (vector, theme-aware via `prefers-color-scheme`)
- `public/icons/icon.svg` (master)
- `public/icons/icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (PWA manifest)
- `public/icons/apple-touch-icon.png` (180px)
- `public/manifest.webmanifest` (with the icons array wired)
- `public/og-static.png` (1200x630 fallback for any URL)
- `src/routes/api/og.ts` (dynamic per-URL OG via Satori on Workers; delegates to `/ro:og-image-dynamic` if not yet wired)
- Head meta tags in `src/routes/__root.tsx`: `og:*`, `twitter:*`, `link rel="icon"`, `link rel="manifest"`, `link rel="apple-touch-icon"`, theme-color, JSON-LD application schema

## When to use

- New app: scaffold the whole asset set on day one. Spec must include this story (the baseline checklist enforces it).
- Existing app: audit + fix gaps. Run with `--audit-only` to report what's missing without writing.

## When NOT to use

- Native mobile apps (Expo / React Native): different asset pipeline (use Expo's icon/splash conventions).
- Pure CLI tools or libraries with no public-facing URL: nothing to share.

## Why this is a baseline

Every link a customer or investor pastes into X / Reddit / LinkedIn / WhatsApp / iMessage / Slack triggers an OpenGraph fetch. The default "no preview" rendering looks broken; a wrong-aspect-ratio static image looks lazy; a per-URL dynamic image looks polished. Same with the favicon: a default Vite/Next.js placeholder favicon is the visual equivalent of a "Hello World" landing page.

Fix once, fix permanently, automate the rest.

## Usage

```
/ro:share-assets --source brand/dataforce-mark.svg dataforce
/ro:share-assets --source ./logo.svg --brand-color "#10b981" my-app
/ro:share-assets --no-dynamic-og my-app          # skip the /api/og route, static-only
/ro:share-assets --audit-only                    # report gaps; don't write
```

If `--source` is omitted, the skill prompts (AskUserQuestion) for an existing brand mark path or offers to call `/ro:generate-image` to create one from a brief.

## Step 1 — Source mark check

Verify the source SVG:
- Square aspect ratio
- Single-coloured OR explicitly designed for monochrome (favicon will be reduced to 2 colours)
- No outer padding (the skill adds appropriate safe-zones for maskable icons)
- Valid XML

If the source fails, prompt for a different path or call `/ro:generate-image` with a "brand mark, square, single-colour, modern" prompt.

## Step 2 — Generate the favicon set

Use ImageMagick (`magick` on macOS / `convert` on Linux) or `sharp` (Node) to derive PNGs at 16, 32, 48, 180, 192, 512. Bundle the 16/32/48 PNGs into a multi-resolution `favicon.ico`:

```bash
magick -density 300 -background none source.svg \
  -define icon:auto-resize=16,32,48 public/favicon.ico

magick -density 300 -background none source.svg -resize 180x180 public/icons/apple-touch-icon.png
magick -density 300 -background none source.svg -resize 192x192 public/icons/icon-192.png
magick -density 300 -background none source.svg -resize 512x512 public/icons/icon-512.png

# Maskable: pad with 20% safe zone on all sides
magick -density 300 -background "#<brand-color>" source.svg \
  -resize 320x320 -gravity center -extent 512x512 \
  public/icons/icon-maskable-512.png

cp source.svg public/favicon.svg
cp source.svg public/icons/icon.svg
```

Theme-aware favicon (optional but nice): the SVG can use `<style>` with `prefers-color-scheme: dark` so the favicon adapts to the user's OS. Document this in the source.

## Step 3 — Generate the static OG image

`public/og-static.png` is the fallback when `/api/og` isn't reachable or for very old crawlers. 1200x630, brand-coloured, with the app name and a one-line tagline.

If the user already has a designed marketing hero, derive from that. Otherwise compose a minimal layout:

```bash
magick -size 1200x630 \
  -background "#<brand-color>" \
  -fill white \
  -font Inter-Bold \
  -pointsize 92 \
  -gravity center \
  -annotate 0 "<App Name>" \
  public/og-static.png
```

## Step 4 — Wire `manifest.webmanifest`

```json
{
  "name": "<App Name>",
  "short_name": "<Short>",
  "description": "<one-line description>",
  "start_url": "/?source=pwa",
  "scope": "/",
  "display": "standalone",
  "display_override": ["standalone", "browser"],
  "background_color": "#ffffff",
  "theme_color": "#<brand-color>",
  "orientation": "portrait-primary",
  "categories": ["productivity"],
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

## Step 5 — Wire head meta tags (TanStack Start)

In `src/routes/__root.tsx` head function:

```ts
const SITE_ORIGIN = 'https://<your-domain>'
const TITLE = '<App Name>: <one-line tagline>'
const DESCRIPTION = '<150-character description>'
const OG_IMAGE = `${SITE_ORIGIN}/api/og` // dynamic; falls back to /og-static.png if route unreachable

head: () => ({
  meta: [
    { charSet: 'utf-8' },
    { name: 'viewport', content: 'width=device-width, initial-scale=1' },
    { title: TITLE },
    { name: 'description', content: DESCRIPTION },
    { name: 'theme-color', content: '#<brand-color>' },

    // OpenGraph
    { property: 'og:type', content: 'website' },
    { property: 'og:site_name', content: '<App Name>' },
    { property: 'og:title', content: TITLE },
    { property: 'og:description', content: DESCRIPTION },
    { property: 'og:url', content: SITE_ORIGIN },
    { property: 'og:image', content: OG_IMAGE },
    { property: 'og:image:width', content: '1200' },
    { property: 'og:image:height', content: '630' },

    // Twitter / X
    { name: 'twitter:card', content: 'summary_large_image' },
    { name: 'twitter:title', content: TITLE },
    { name: 'twitter:description', content: DESCRIPTION },
    { name: 'twitter:image', content: OG_IMAGE },
  ],
  links: [
    { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' },
    { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico' },
    { rel: 'apple-touch-icon', href: '/icons/apple-touch-icon.png' },
    { rel: 'manifest', href: '/manifest.webmanifest' },
  ],
  scripts: [
    {
      type: 'application/ld+json',
      children: JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'WebApplication',
        name: '<App Name>',
        url: SITE_ORIGIN,
        description: DESCRIPTION,
        applicationCategory: '<Productivity / Game / Tool>',
        operatingSystem: 'Web',
      }),
    },
  ],
})
```

## Step 6 — Dynamic OG route (if not skipped)

Delegates to the `/ro:og-image-dynamic` skill for the implementation. The skill scaffolds `src/routes/api/og.ts` using Satori + `@resvg/resvg-wasm` on Workers.

When this skill (`/ro:share-assets`) runs and the OG route doesn't exist yet, it invokes `/ro:og-image-dynamic --runtime cf` automatically. Pass `--no-dynamic-og` to skip and stick with the static `og-static.png`.

## Step 7 — Verify

After scaffolding, the skill runs:

```bash
curl -sI https://<deployed-url>/favicon.ico  # 200 image/x-icon
curl -sI https://<deployed-url>/favicon.svg  # 200 image/svg+xml
curl -sI https://<deployed-url>/manifest.webmanifest  # 200 application/manifest+json
curl -sI https://<deployed-url>/og-static.png  # 200 image/png, ~30-80kb
curl -sI https://<deployed-url>/api/og  # 200 image/png if dynamic wired
```

And renders the head + checks:

```bash
curl -s https://<deployed-url> | grep -E 'og:image|twitter:card|rel="(icon|manifest|apple-touch)"'
```

Then opens https://www.opengraph.xyz/?url=https://<deployed-url> and https://cards-dev.twitter.com/validator (if it still exists) to visually verify the share preview.

## Audit mode

`--audit-only` reports what's missing without writing:

```
✓ favicon.svg
✓ favicon.ico
✗ apple-touch-icon.png (missing)
✓ manifest.webmanifest
✗ icon-maskable-512.png (missing; manifest references it)
✗ /api/og route (no dynamic OG)
✓ og-static.png
✓ Head meta tags (og:*, twitter:*)
✗ JSON-LD application schema (missing in __root.tsx)
```

Returns exit code 0 if all present, 1 if any missing. Useful in CI as a launch-readiness gate.

## What this skill does NOT do

- Design the brand mark (delegate to `/ro:generate-image` or use an existing source).
- Ship per-route OG titles (different feature; emit a `useHead()` pattern in route components, scoped to each story).
- Replace `/ro:seo-launch-ready` (which handles sitemap, robots, JSON-LD basics, canonical URLs).
- Replace `/ro:pwa-install` (which handles service worker + install prompt).

## Related

- `[[ideal-tech-setup]]` § Greenfield Spec Baseline — share-assets is item #11
- `/ro:og-image-dynamic` — wires the per-URL dynamic OG route
- `/ro:seo-launch-ready` — sitemap, robots, JSON-LD, canonical URLs
- `/ro:pwa-install` — manifest + service worker for installability
- `/ro:app-polish` — 10-point launch-readiness audit (this skill is one of the points)
