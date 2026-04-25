---
name: linkedin
description: Manage your LinkedIn via the official API — create posts, fetch your profile, and draft copy for bio/experience edits. Use when user wants to post to LinkedIn, share an update, check their LinkedIn identity, or revise their profile/headline/about.
category: social
argument-hint: <auth | post <text> | me | draft <about|headline|experience|education|skills> [text]>
allowed-tools: Bash(curl *) Bash(python3 *) Bash(open *) Bash(pbcopy) Read Write Edit
content-pipeline:
  - pipeline:distribution
  - platform:linkedin
  - role:adapter
---

# LinkedIn

Official LinkedIn API (OAuth 2.0) for creating posts from your personal profile. Profile-section edits (bio, experience, jobs) have **no public write API** — handled in draft-only mode: the skill generates the copy, copies it to clipboard, and opens the LinkedIn edit UI for you to paste + save.

## Usage

```
/ro:linkedin auth                                   # one-time OAuth (token lasts ~60 days)
/ro:linkedin post "Hello LinkedIn 👋"                # publish a text post to your feed
/ro:linkedin me                                     # show profile identity (userinfo)
/ro:linkedin draft about "New about-section copy..." # draft-edit mode: clipboard + open editor
/ro:linkedin draft headline "Staff Engineer @ ..."
/ro:linkedin draft experience                       # just open the add-position form
```

## Dispatch

| Arg | Script |
|-----|--------|
| `auth` | `scripts/auth.py` |
| `post <text>` | `scripts/post.sh` |
| `me` | `scripts/me.sh` |
| `draft <section> [text]` | `scripts/draft-edit.sh` |

Pass all trailing args through verbatim.

## First-time setup

1. **LinkedIn developer app** — https://www.linkedin.com/developers/apps
   - Products tab → request **"Sign In with LinkedIn using OpenID Connect"** and **"Share on LinkedIn"** (both usually auto-approve)
   - Auth tab → Authorized redirect URLs → add `http://localhost:8765/callback`
2. **Credentials** — write to `~/.claude/.env`:
   ```
   LINKEDIN_CLIENT_ID=...
   LINKEDIN_CLIENT_SECRET=...
   ```
   Then `chmod 600 ~/.claude/.env`.
3. **Run OAuth**: `/ro:linkedin auth` — browser opens, you approve, token is written back to `~/.claude/.env`.

The access token lasts ~60 days. `post` / `me` warn when <7 days remain and fail hard when expired — re-run `auth` to refresh.

## What this skill does NOT do

- **Read bio / experience / about text** — OIDC only returns name/email/picture. For the actual text use `/ro:linkedin-voyager profile <slug>` (ToS-grey).
- **Bio / experience / headline / about edits** — LinkedIn's Profile Edit API is partner-only. `draft` mode is the answer: the skill generates the copy, `pbcopy`s it, and `open`s the right LinkedIn form URL. You paste + save.
- **Company-page posts** — would need `w_organization_social` scope + an org URN. Not wired. Ask to extend.
- **Messaging, connections, comments, reactions** — not in the `w_member_social` scope. LinkedIn restricts these to partners. Use the paid `linkedin-cli` (Linked API) if you need them.
- **Analytics beyond basic profile info** — needs additional scopes / products not requested here.

## Security

- Client secret and access token live only in `~/.claude/.env` (mode 0600). Never committed.
- `auth.py` only binds to `localhost` and validates the OAuth `state` parameter.
- The skill never echoes the secret or the full token in output (only the last 4 chars for debugging).

## Details

See `reference.md` for: OAuth flow internals, `/rest/posts` request shape, error codes, scope reference, and how to extend for company pages.

## See also

- `ro:linkedin-scan` — read-only LinkedIn scraper (light, public-facing HTML).
- `ro:linkedin-voyager` — ToS-grey sibling: reads bio/experience/full profile via the unofficial Voyager API using browser cookies. Use when the official API can't give you what you need. Ban risk — see its SKILL.md.
- `ro:browser-cookies` — shared cookie extractor used by scan + voyager.
- `ro:write-copy` — apply style rules before drafting a post or about section.
