---
name: linkedin-voyager
description: Read LinkedIn profile data (bio, headline, experience, education, skills, contacts) via the unofficial Voyager API. Uses your browser session cookies — NO password. Sibling to the official-API `linkedin` skill. Use when user wants to see or export their own (or a public) profile content not available in the official API.
category: social
argument-hint: <profile <slug> | contact <slug> | search <keywords> | connections>
allowed-tools: Bash(uv *) Bash(python3 *) Read
disable-model-invocation: true
content-pipeline:
  - pipeline:scan
  - platform:linkedin
  - role:scanner
---

# LinkedIn Voyager (unofficial)

Read-side sibling to `ro:linkedin`. Hits LinkedIn's internal **Voyager** API (same API the linkedin.com web app uses) via the `linkedin-api` Python library (tomquirk). Gives access to profile sections the official OAuth API doesn't expose: About, Headline, Experience, Education, Skills, Certifications, Contact info, Connections, etc.

## ⚠️ Terms of service + ban risk

This skill uses an **undocumented internal API** and authenticates with your **session cookies**. Per LinkedIn's User Agreement §8.2, automated access that is not through their public API is prohibited. Aggressive or high-volume usage has resulted in account restrictions or bans. Use sparingly:

- Prefer `/ro:linkedin` (official API) for anything it covers.
- Keep request rate low. One profile fetch per minute is fine; a scripted crawl is not.
- This skill is `disable-model-invocation: true` — Claude will never call it without your typed `/ro:linkedin-voyager ...`.

## Usage

```
/ro:linkedin-voyager profile ronanconnolly        # your own profile (bio/headline/experience/skills)
/ro:linkedin-voyager profile satyanadella         # any public profile slug
/ro:linkedin-voyager contact ronanconnolly        # email/phone/twitter if the viewer can see them
/ro:linkedin-voyager search "staff engineer"      # people search (limited)
/ro:linkedin-voyager connections                  # the viewer's own 1st-degree connections
```

## Auth — session cookies, no password

On every run, `scripts/voyager.py` extracts `li_at` + `JSESSIONID` from the browser set by `ROBROWSER` in `~/.config/ro/defaults.env` (or `--browser <name>`), using `browser_cookie3`. No password is ever prompted or stored. Cookies stay in memory.

If the library rejects the cookies (LinkedIn sometimes requires challenges), log into linkedin.com once in the browser and retry.

## Output

Profile output (default — compact human-readable):

```
# <Full Name>  —  <Headline>
<location> · <industry>
linkedin.com/in/<slug>

## About
<bio text>

## Experience
- <Title> @ <Company>  (<start> – <end or Present>)  <location>
  <description if any>
- ...

## Education
- <School> — <Degree> <Field>  (<years>)

## Skills
skill1, skill2, skill3, ...
```

Add `--json` for raw Voyager JSON (huge — useful for wiki ingest or diffs).

## Dispatch

| Arg | Function |
|-----|----------|
| `profile <slug>` | `get_profile(public_id=slug)` + pretty-printer |
| `contact <slug>` | `get_profile_contact_info(public_id=slug)` |
| `search <terms>` | `search_people(keywords=terms, limit=10)` |
| `connections`    | `get_profile_connections(<viewer>)` |

## Execution

```bash
uv run --with 'linkedin-api>=2.3' --with browser-cookie3 python3 \
  /path/to/skills/linkedin-voyager/scripts/voyager.py <cmd> <args...>
```

`uv` provisions the deps on first run; subsequent runs are fast.

## TODO / known limits of `profile`

- Current implementation uses dash endpoint `FullProfile-138` which returns the **top card only**: name, headline, summary (About/bio), location, profile picture.
- Experience, education, skills, certifications, languages live on separate dash sub-endpoints (e.g. `/identity/dash/profilePositions?viewee=<urn>&...`). Not yet wired. Add as a second call chained after the top card if the caller wants the full profile.
- Library's own `get_profile()` hits `/identity/profiles/<slug>/profileView` which returns **410 Gone** as of 2026-Q1. Don't use it — this skill's `cmd_profile` calls the dash endpoint directly.

## Limits & failure modes

- **Rate limit / challenge** — LinkedIn may serve a CAPTCHA. Log into linkedin.com in the browser, solve it, retry.
- **Fields missing** — Voyager returns what the authenticated viewer can see. Private profiles return a stub.
- **Library drift** — LinkedIn rotates internal endpoints; `linkedin-api` is usually patched within weeks. `uv` auto-picks the latest compatible version per run.
- **Account flag** — heavy usage = temp restriction. Don't loop this skill. If responses start returning `Set-Cookie: li_at=delete me` + infinite 302 loops to the same URL, LinkedIn has invalidated the session server-side. Log back into the browser and wait ~30 min before retrying.
- **Cookie quirk (fixed in scripts/voyager.py)** — Chromium stores LinkedIn cookies with domain `.www.linkedin.com` and quoted JSESSIONID values like `"ajax:..."`. requests' cookiejar won't send `.www.linkedin.com`-scoped cookies to host `www.linkedin.com`, and the quoted JSESSIONID won't match the `csrf-token` header (which is set unquoted). Both caused 403 "CSRF check failed" until `get_cookies()` rebuilt the jar with `.linkedin.com` domain + stripped JSESSIONID quotes.

## See also

- `/ro:linkedin` — official OAuth API: posts + draft-mode profile edits. Start there.
- `/ro:linkedin-scan` — light scraping of the public-facing HTML (even safer, less structured).
- `/ro:browser-cookies` — the underlying cookie path this skill uses.
- Upstream: https://github.com/tomquirk/linkedin-api
