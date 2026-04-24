---
name: cloudflare-setup
description: One-time Cloudflare API token setup so other skills (domain, cloudflare-dns, cf-ship) can create zones, edit DNS, manage Workers, and write redirect rules. Use when a Cloudflare skill fails with "Authentication error" or when onboarding a new machine. Walks the user through the account-owned token + user token model that Cloudflare requires.
category: project-setup
argument-hint: [--verify | --reset]
allowed-tools: Bash(curl *) Bash(jq *) Read Write Edit
---

# Cloudflare Setup

One-time setup. Mints the two API tokens the automation skills need and writes them to `~/.claude/.env`. Run when:

- A Cloudflare skill fails with `Authentication error` (code `10000`) or `request is not authorized`
- You're onboarding a new machine and don't have `CLOUDFLARE_API_TOKEN_*` set
- You want to audit what scopes the current tokens actually have

## Usage

```
/ro:cloudflare-setup              # full interactive setup
/ro:cloudflare-setup --verify     # test both tokens, report what works
/ro:cloudflare-setup --reset      # clear existing values and start fresh
```

## Why two tokens?

Cloudflare has two *kinds* of API token and they expose different permissions. This is the single biggest source of confusion when automating Cloudflare — missing it costs 30+ minutes of dashboard clicking.

| Token type | Created at | Can do |
|------------|-----------|--------|
| **User token** | `/profile/api-tokens` | Day-to-day zone config: DNS edits, rulesets, worker deploys, worker custom domains |
| **Account-owned token** | Account → Manage Account → API Tokens | **Zone creation** (`com.cloudflare.api.account.zone.create`), account-level scopes that aren't available via user tokens |

You need both because:
- Zone creation (adding a newly registered domain to Cloudflare) needs the account-owned token — this permission **does not appear** in the user-token UI.
- Redirect Rules, DNS edits, worker attachment — all live on the user-token side.

The Global API Key is a third option that can do everything, but it's also all-access (billing, account delete, zero-scope). Avoid unless you have a very specific reason.

## Env var layout

Writes to `~/.claude/.env`:

```bash
# Account-owned — for onboarding new domains (zone creation, account-level ops)
CLOUDFLARE_API_TOKEN_ZONE_CREATE=cfat_...   # prefix cfat_ = account-owned
CLOUDFLARE_ACCOUNT_ID=...

# User token — for day-to-day DNS, Worker, redirect rule management
CLOUDFLARE_API_TOKEN_ADMIN=cfut_...          # prefix cfut_ = user token
CLOUDFLARE_ZONE_ID=...                       # optional: primary zone you deploy to

# Legacy — kept for backwards-compat with older skills
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN_ADMIN
```

The `cfat_` vs `cfut_` prefix is the fastest way to tell them apart when reading `.env`. `cfat_` = account (admin), `cfut_` = user.

## Process

### 1. Pre-check

```bash
source ~/.claude/.env 2>/dev/null
echo "ZONE_CREATE:  ${CLOUDFLARE_API_TOKEN_ZONE_CREATE:+set}${CLOUDFLARE_API_TOKEN_ZONE_CREATE:-missing}"
echo "ADMIN:        ${CLOUDFLARE_API_TOKEN_ADMIN:+set}${CLOUDFLARE_API_TOKEN_ADMIN:-missing}"
echo "ACCOUNT_ID:   ${CLOUDFLARE_ACCOUNT_ID:+set}${CLOUDFLARE_ACCOUNT_ID:-missing}"
```

If all three are set, offer `--verify` as the likely next step. If any missing, proceed to mint them.

### 2. Find the Account ID

Easiest path — the user can read it off the dashboard: https://dash.cloudflare.com → any zone → right sidebar "API" section → **Account ID**. Paste to you.

Alternatively, if they already have *any* valid API token, fetch it:

```bash
curl -s "https://api.cloudflare.com/client/v4/accounts" \
  -H "Authorization: Bearer $EXISTING_TOKEN" \
  | jq -r '.result[] | "\(.id)  \(.name)"'
```

If there's only one account, use it. Otherwise ask the user which.

### 3. Mint the account-owned token (zone creation)

**This lives in a different place than the user-profile tokens. UI path:**

1. https://dash.cloudflare.com → click your account name (top left, not the profile icon)
2. Left sidebar: **Manage Account** → **API Tokens**
3. **Create Token** → **Custom Token** → **Get started**
4. Name: `zone-bootstrap` (or any descriptive name)
5. Permissions — add these two rows:
   - **Zone** → **Write** (this is the one that enables zone *creation* — only visible here)
   - **Workers Scripts** → **Write** (for attaching the new zone to a Worker via custom domain)
6. Optional extra (for redirect rule automation): **Dynamic URL Redirects** → **Write** (saves an extra token edit later)
7. **Account Resources**: leave as "All zones in [your account]"
8. **Continue to summary** → **Create Token** → **copy the token** (shown once)

Save:

```bash
echo 'CLOUDFLARE_API_TOKEN_ZONE_CREATE=<paste-cfat-token>' >> ~/.claude/.env
echo 'CLOUDFLARE_ACCOUNT_ID=<account-id>' >> ~/.claude/.env
```

Verify it works with an authenticated call (account-owned tokens do *not* work against `/user/tokens/verify`, so test with a real call):

```bash
source ~/.claude/.env
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=1" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ZONE_CREATE" \
  | jq '{success, errors}'
```

`success: true` means the token is valid. Auth errors mean the token wasn't saved correctly or the scope is wrong.

### 4. Mint the user token (day-to-day ops)

**UI path:**

1. https://dash.cloudflare.com → profile icon (top right) → **Profile** → **API Tokens**
2. **Create Token** → **Custom Token**
3. Name: `claude-skills` (or similar)
4. Permissions — add these rows:
   - **Account** → **Workers Scripts** → **Edit**
   - **Zone** → **Zone** → **Read**
   - **Zone** → **DNS** → **Edit**
   - **Zone** → **Config Rules** → **Edit** *(for ruleset management)*
   - **Zone** → **Dynamic URL Redirect** → **Edit** *(for 301/302 redirect rules — a separate permission from Config Rules, easy to miss)*
5. **Account Resources**: Include → your account
6. **Zone Resources**: Include → All zones from your account
7. **Continue to summary** → **Create Token**

Save:

```bash
echo 'CLOUDFLARE_API_TOKEN_ADMIN=<paste-cfut-token>' >> ~/.claude/.env
# Maintain backwards-compat for skills that read the legacy name:
echo 'CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN_ADMIN' >> ~/.claude/.env
```

Verify:

```bash
source ~/.claude/.env
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" \
  | jq '{success, status: .result.status}'
```

Expect `success: true, status: "active"`.

### 5. (Optional) Save primary zone ID

If there's a "main" zone you deploy to repeatedly, cache its ID to skip lookups:

```bash
PRIMARY_ZONE=<your-main-domain.com>
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$PRIMARY_ZONE" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" | jq -r '.result[0].id')
echo "CLOUDFLARE_ZONE_ID=$ZONE_ID" >> ~/.claude/.env
```

### 6. `--verify` mode

Run both tokens through a minimal set of calls to prove each scope:

```bash
source ~/.claude/.env

echo "--- account-owned token (zone create) ---"
curl -s "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ZONE_CREATE" \
  | jq '{success, name: .result.name}'

echo "--- user token: list zones ---"
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=5" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" \
  | jq '{success, count: (.result|length)}'

# Pick any zone id you own, then:
echo "--- user token: read rulesets (Config Rules) ---"
curl -s "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/rulesets" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" \
  | jq '{success}'

echo "--- user token: read dynamic redirect phase ---"
curl -s "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" \
  | jq '{success, errors}'
```

Expected:
- All `success: true` → fully set up.
- Rulesets list `success: true` but phase entrypoint `10003 "could not find entrypoint"` → **authorized but no rule exists yet** (this is fine, not an error).
- Any `10000` (Authentication error) → token is missing that scope. Re-check UI.

### 7. `--reset` mode

Back up the current `.env`, then remove the Cloudflare block:

```bash
cp ~/.claude/.env ~/.claude/.env.bak.$(date +%Y%m%d-%H%M%S)
# Strip any line starting with CLOUDFLARE_
sed -i.tmp '/^CLOUDFLARE_/d' ~/.claude/.env && rm ~/.claude/.env.tmp
```

Then restart at step 2.

## Common failures and how to diagnose

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Authentication error` (10000) on zone create | Using a user token for `POST /zones` | Switch to the account-owned (`cfat_`) token |
| `Authentication error` on redirect rule PUT | User token missing Dynamic URL Redirect scope | Edit the user token, add **Dynamic URL Redirect > Edit** |
| `request is not authorized` on specific phase | Token has Config Rules but not Dynamic URL Redirect | Same — they are *separate* permissions despite being adjacent features |
| `could not find entrypoint ruleset` (10003) | No error — just means no rule has been created yet | Continue; first PUT creates it |
| `Invalid API Token` on any call | Wrong token pasted, or trailing whitespace | Re-check the saved value with `grep ^CLOUDFLARE ~/.claude/.env` |

## What this skill does NOT handle

- Rotating tokens — do that in the UI and update `~/.claude/.env` manually
- Migrating away from the Global API Key — that's a one-time manual port
- Per-project `.dev.vars` (wrangler secrets) — different concept; see `/ro:cf-ship`

## See also

- `/ro:domain` — register domains on Porkbun, ties into this skill for the NS handoff to Cloudflare
- `/ro:cloudflare-dns` — day-to-day DNS edits (uses the user token from step 4)
- `/ro:cf-ship` — deploy a Worker (uses the user token)
- Cloudflare API tokens reference: https://developers.cloudflare.com/api/tokens/
