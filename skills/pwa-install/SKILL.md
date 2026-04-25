---
name: pwa-install
description: Turn a web app into an installable Progressive Web App. Wires a web manifest, minimal service worker (network-first for HTML, cache-first for assets), icons, and an install-prompt component. Use for daily-return utilities, dashboards, and any app where "add to home screen" replaces the need for an email list.
category: quality-review
argument-hint: [--runtime cf|vercel|node] [--name <app>] [--theme <hex>] [--no-sw] [--offline]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# PWA Install

Add the three ingredients that make a web app installable: a manifest, a service worker, and a prompt UI. For daily-return apps, this is the single biggest re-engagement lever — installing the app to the home screen turns casual visits into a habit loop without needing auth or email capture.

## Usage

```
/ro:pwa-install                          # auto-detect, default template
/ro:pwa-install --name "Connections"     # custom display name
/ro:pwa-install --theme "#14b8a6"        # theme colour
/ro:pwa-install --no-sw                  # manifest only (no offline)
/ro:pwa-install --offline                # add offline fallback page + richer caching
```

## Step 0: Preflight (skip if already wired)

Before scaffolding anything, check what's already there. If all four core pieces exist, **stop and report "PWA already wired"** with the file list, instead of dumping the recipe. The user can pass `--force` to re-scaffold.

```bash
test -f "$REPO/public/manifest.webmanifest" -o -f "$REPO/public/manifest.json" && echo "✓ manifest"
test -f "$REPO/public/sw.js" -o -f "$REPO/public/service-worker.js" -o -d "$REPO/public/workbox-*" && echo "✓ service worker"
ls "$REPO"/public/icons/icon-{192,512}.png 2>/dev/null && echo "✓ icons"
grep -rqE "navigator\.serviceWorker\.register|workbox-window" "$REPO/src" && echo "✓ SW registration"
grep -qE "rel=\"manifest\"|rel: 'manifest'" "$REPO"/src/routes/__root.* 2>/dev/null && echo "✓ manifest link in root"
```

Report each as ✓ / ✗. If 4+ of 5 are ✓, say "PWA already wired; nothing to scaffold. Audit: [list]. Use `--force` to re-scaffold or pick the missing piece by hand." Skip the rest of the steps.

If partially wired (1-3 of 5 ✓), tell the user which pieces exist and ask whether to fill the gaps or re-scaffold from scratch.

## What gets wired

1. **`public/manifest.webmanifest`** — app metadata, icons, display mode, theme colour.
2. **`public/sw.js`** — minimal service worker with sensible defaults.
3. **`public/icons/icon-192.png` + `icon-512.png`** — generated from an existing favicon or prompted.
4. **Meta tags** in `src/routes/__root.tsx` — `link rel="manifest"`, theme-color, apple-touch-icon.
5. **Install prompt component** (`src/components/InstallPrompt.tsx`) — detects `beforeinstallprompt`, shows an unobtrusive toast.
6. **Registration call** in the client entry point.

## 1. `public/manifest.webmanifest`

```json
{
  "name": "Connections Helper",
  "short_name": "Connections",
  "description": "NYT Connections puzzle sidekick.",
  "start_url": "/?source=pwa",
  "display": "standalone",
  "display_override": ["window-controls-overlay", "standalone", "browser"],
  "background_color": "#ffffff",
  "theme_color": "#14b8a6",
  "orientation": "portrait-primary",
  "categories": ["games", "puzzles", "utilities"],
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "screenshots": [
    { "src": "/screenshots/desktop.png", "sizes": "1280x720", "type": "image/png", "form_factor": "wide" },
    { "src": "/screenshots/mobile.png", "sizes": "390x844", "type": "image/png", "form_factor": "narrow" }
  ]
}
```

**`start_url` with `?source=pwa`** lets analytics distinguish standalone opens from browser opens (useful to measure install conversion).

**Maskable icon:** Android adaptive icons mask to the platform shape. Without a maskable icon, Android crops your icon badly. Generate via `npx pwa-asset-generator` or a manual mask-safe design (content inside 60% centre).

## 2. `public/sw.js` — default service worker

Two strategies depending on app shape:

**Network-first for HTML (content apps, dashboards, daily utilities).** Fresh content is the priority; offline is a fallback.

```js
const CACHE = 'app-v1'
const ASSETS = ['/', '/offline']

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)))
  self.skipWaiting()
})

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))),
    ),
  )
  self.clients.claim()
})

self.addEventListener('fetch', (e) => {
  const { request } = e
  if (request.method !== 'GET') return

  // Network-first for HTML documents
  if (request.mode === 'navigate' || request.headers.get('accept')?.includes('text/html')) {
    e.respondWith(
      fetch(request)
        .then((r) => {
          const clone = r.clone()
          caches.open(CACHE).then((c) => c.put(request, clone))
          return r
        })
        .catch(() => caches.match(request).then((r) => r ?? caches.match('/offline'))),
    )
    return
  }

  // Cache-first for static assets (immutable hashed filenames from Vite)
  if (/\.(js|css|woff2?|png|svg|webp|avif|jpg|jpeg)$/.test(new URL(request.url).pathname)) {
    e.respondWith(
      caches.match(request).then((cached) => {
        if (cached) return cached
        return fetch(request).then((r) => {
          const clone = r.clone()
          caches.open(CACHE).then((c) => c.put(request, clone))
          return r
        })
      }),
    )
    return
  }

  // Everything else (API calls): network-only, no caching.
})
```

**Cache-first for everything (fully offline-first apps, e.g. a note-taking PWA)** — flip the defaults. Use Workbox (`workbox-window`) if the caching logic is getting complex; handwritten SW is fine up to about 50 lines.

**Never cache API responses generically** — it'll serve stale data after a deploy. If you need API caching, do it in the server with `Cache-Control: s-maxage=...`, not in the SW.

## 3. Meta tags + manifest link

In `src/routes/__root.tsx` (or equivalent `<head>` location):

```tsx
head: () => ({
  links: [
    { rel: 'manifest', href: '/manifest.webmanifest' },
    { rel: 'icon', href: '/icons/icon-192.png', sizes: '192x192' },
    { rel: 'apple-touch-icon', href: '/icons/icon-192.png' },
  ],
  meta: [
    { name: 'theme-color', content: '#14b8a6' },
    { name: 'mobile-web-app-capable', content: 'yes' },
    { name: 'apple-mobile-web-app-capable', content: 'yes' },
    { name: 'apple-mobile-web-app-status-bar-style', content: 'black-translucent' },
  ],
}),
```

## 4. Service worker registration

In the client entry (`src/client.tsx` or `src/app.tsx`):

```ts
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((err) => {
      console.warn('SW registration failed:', err)
    })
  })
}
```

**Prod only.** A registered SW in dev caches your HMR bundles and turns every hot-reload into a confused mess.

## 5. Install prompt component

```tsx
// src/components/InstallPrompt.tsx
import { useEffect, useState } from 'react'
import { track } from '@/lib/posthog' // if using /ro:posthog

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export function InstallPrompt() {
  const [event, setEvent] = useState<BeforeInstallPromptEvent | null>(null)
  const [dismissed, setDismissed] = useState(
    () => typeof window !== 'undefined' && localStorage.getItem('pwa-install-dismissed') === 'true',
  )

  useEffect(() => {
    const onBeforeInstall = (e: Event) => {
      e.preventDefault()
      setEvent(e as BeforeInstallPromptEvent)
    }
    window.addEventListener('beforeinstallprompt', onBeforeInstall)
    return () => window.removeEventListener('beforeinstallprompt', onBeforeInstall)
  }, [])

  if (!event || dismissed) return null

  const install = async () => {
    await event.prompt()
    const { outcome } = await event.userChoice
    track?.('cta_clicked', { cta: 'pwa_install', location: `prompt:${outcome}` })
    setEvent(null)
  }

  const dismiss = () => {
    localStorage.setItem('pwa-install-dismissed', 'true')
    setDismissed(true)
    track?.('cta_clicked', { cta: 'pwa_install_dismiss', location: 'prompt' })
  }

  return (
    <div role="dialog" aria-label="Install this app" className="...">
      <p>Install for one-tap access from your home screen.</p>
      <button onClick={install}>Install</button>
      <button onClick={dismiss} aria-label="Dismiss install prompt">Not now</button>
    </div>
  )
}
```

**Important UX rules:**
- Don't show the prompt on the very first visit. Wait for a second session or one completed primary action ("looked up a definition", "solved a puzzle"). A new-user + install prompt is nagware.
- Respect the dismiss. Don't re-prompt on the next visit; `localStorage` flag is the lightest solution.
- Don't show on iOS — iOS Safari doesn't fire `beforeinstallprompt`. Use a UA check to show a small "Add to Home Screen via Share" hint instead.

## Icon generation

If icons don't exist yet:

```bash
# Using pwa-asset-generator (no install, via npx):
npx pwa-asset-generator ./src/assets/logo.svg ./public/icons \
  --manifest ./public/manifest.webmanifest \
  --background "#ffffff" \
  --padding "10%" \
  --icon-only

# Or manually with ImageMagick from a square source image:
magick logo.png -resize 192x192 public/icons/icon-192.png
magick logo.png -resize 512x512 public/icons/icon-512.png
```

## Testing

```bash
# Local build (SW only runs in prod):
pnpm build && pnpm preview

# In the browser:
# 1. DevTools → Application → Manifest. Verify no warnings.
# 2. DevTools → Application → Service Workers. Verify registered + running.
# 3. DevTools → Lighthouse → PWA audit. Should be green.
# 4. Network tab → throttle to "Offline" → reload. Offline fallback should appear.
```

**Real-device test:** the `beforeinstallprompt` Add-to-Home flow only fires on mobile Chrome and desktop Chrome/Edge. Test on an actual Android device via USB debugging before shipping the install component.

## Gotchas

- **SW scope.** `/sw.js` controls the whole origin. `/foo/sw.js` only controls `/foo/*`. Always serve from the origin root unless you want to scope.
- **Version bumps.** Bumping `CACHE` in `sw.js` is the shipping mechanism. Old clients hold the previous SW until the tab closes — add a "reload for latest version" toast when a new SW activates.
- **Clear caches in dev.** If something is weird, DevTools → Application → Clear storage → Clear site data. SW stickiness is the #1 source of "why is my change not showing up."
- **HTTPS required.** SW won't register on `http://` (localhost is the exception).
- **Cloudflare + SW.** Cloudflare caches your SW file by default, which creates a stale-SW problem on redeploy. Add a page rule or `Cache-Control: no-cache, max-age=0, must-revalidate` for `/sw.js`.

## When NOT to add a PWA

- Static marketing sites. You want SEO, not app-shell. Skip the SW.
- Apps that change structure often. SW caching + rapid redeploys = more cache-mismatch support tickets than it's worth.
- Apps without a daily-return loop. PWA mostly matters when install + re-open is the user behaviour. A one-time tool doesn't need it.

## See also

- `/ro:app-polish` — umbrella; this is check #4
- `/ro:seo-launch-ready` — complementary meta-tag setup
- `/ro:posthog` — track install prompt acceptance via `cta_clicked`
- `/ro:accessibility-ci` — the install prompt needs `role="dialog"` + proper focus
- Lighthouse PWA audit docs: https://web.dev/articles/lighthouse-pwa
