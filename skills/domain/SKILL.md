---
name: domain
description: Search, price, register, and manage domains via the Porkbun API. Use when the user wants to find a cheap domain, check availability across TLDs, buy a domain, list their domains, update nameservers, or manage URL forwarding. Porkbun is the backend; cheap pricing, full API coverage, no IP whitelisting.
category: deployment
argument-hint: <subcommand> [args]
allowed-tools: Bash(curl *) Bash(jq *) Bash(whois *) Bash(dig *) Read Write Edit
---

# Domain (Porkbun)

Cheap domains + a clean REST API. Covers search, pricing, registration, DNS, and nameservers. After buying, you usually want `/ro:cloudflare-dns` to run DNS on Cloudflare (set Porkbun nameservers to Cloudflare's).

## Usage

```
/ro:domain search <name> [--tlds .com,.app,.dev,.io,.xyz]   # availability + price across TLDs
/ro:domain search-bulk name1,name2,name3 [--tlds ...]        # matrix scan: names × TLDs, ranked by cost
/ro:domain prices [--tld .com]                               # live price list (no auth needed)
/ro:domain check <domain>                                    # single availability + exact price
/ro:domain register <domain> [--years 1] [--no-privacy]      # buy it (confirms cost first)
/ro:domain list                                              # all domains in the account
/ro:domain ns <domain>                                       # show nameservers
/ro:domain ns <domain> <ns1> <ns2> [<ns3> <ns4>]             # update nameservers
/ro:domain ns-cloudflare <domain>                            # end-to-end: create CF zone, push NS to Porkbun
/ro:domain bootstrap <domain> [--worker <name>]              # buy + CF zone + NS switch + optional Worker attach
/ro:domain forward <domain> <target-url>                     # add URL forwarding
/ro:domain dns-list <domain>                                 # list DNS records on Porkbun's NS
```

## Prerequisites

### 1. Porkbun account + API keys

- Sign up at https://porkbun.com, verify email and phone (required for API registration)
- Go to https://porkbun.com/account/api → generate a key pair
- Also tick **"API Access"** on each domain you want the API to manage (per-domain toggle in the domain's management page)

**Important Porkbun quirk**: the account must have at least one domain previously registered before `domain/create` will succeed via API. The first domain has to be bought through the web UI. After that, API registration works.

### 2. Save credentials

```bash
mkdir -p "$CLAUDE_PLUGIN_DATA" && chmod 700 "$CLAUDE_PLUGIN_DATA"
cat >> "$CLAUDE_PLUGIN_DATA/.env" <<'EOF'
PORKBUN_API_KEY=pk1_...
PORKBUN_SECRET_API_KEY=sk1_...
EOF
chmod 600 "$CLAUDE_PLUGIN_DATA/.env"
```

The skill loads from (in order): `$CLAUDE_PLUGIN_DATA/.env`, `~/.claude/.env`, project root `.env`, shell env.

### 3. Verify

```bash
curl -sX POST https://api.porkbun.com/api/json/v3/ping \
  -H 'Content-Type: application/json' \
  -d "{\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_API_KEY\"}" \
  | jq .
```
Expect `{"status":"SUCCESS","yourIp":"..."}`. If you get `Invalid API Key`, the key pair is wrong or API access is disabled on all domains.

## API basics

- Base URL: `https://api.porkbun.com/api/json/v3`
- **Every request is POST**, even for reads
- Auth goes in the JSON body: `{"apikey": "...", "secretapikey": "...", ...other fields}`
- Public endpoint (no auth): `POST /pricing/get`

Build a reusable body template once per session:

```bash
AUTH="\"apikey\":\"$PORKBUN_API_KEY\",\"secretapikey\":\"$PORKBUN_SECRET_API_KEY\""
```

Then inject with `-d "{$AUTH}"` or `-d "{$AUTH,\"field\":\"value\"}"`.

## Subcommand recipes

### `prices` — live TLD pricing

Public endpoint, no auth:

```bash
curl -sX POST https://api.porkbun.com/api/json/v3/pricing/get | jq '.pricing'
```

Returns `{tld: {registration, renewal, transfer}}`. Filter and sort:

```bash
curl -sX POST https://api.porkbun.com/api/json/v3/pricing/get \
  | jq -r '.pricing | to_entries | map({tld:.key, reg:(.value.registration|tonumber)}) | sort_by(.reg) | .[0:20][] | "\(.tld): $\(.reg)"'
```

Top-20 cheapest by first-year registration. Good for finding `.xyz`-style cheap TLDs the user might not have considered.

### `search` — single name across TLDs

Default TLDs if user doesn't pass `--tlds`: `.com,.app,.dev,.io,.xyz,.co,.net,.org`.

For each TLD, hit `checkDomain`:

```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/checkDomain/$NAME.$TLD" \
  -H 'Content-Type: application/json' \
  -d "{$AUTH}" | jq '{domain: "'$NAME.$TLD'", available: .response.avail, price: .response.price, premium: .response.premium}'
```

`response.avail` is `"yes"` / `"no"`. Premium domains cost multiples of the base price; flag them so the user doesn't accidentally buy a $500 `.com`.

**Rate limit**: `checkDomain` is capped at **1 request per 10 seconds per API key** (Porkbun, as of 2026-04). Sleep 11s between calls or the server returns `"1 out of 1 checks within 10 seconds used"`. For bulk scans, first filter with `whois` / `dig NS` (free, no rate limit) to a shortlist, then run `checkDomain` on the survivors for exact pricing. Never run in parallel; you'll get throttled immediately.

### `search-bulk` — matrix scan

Names × TLDs, filter to available, rank by price ascending. Useful for "give me the cheapest available from this shortlist." Example output:

```
AVAILABLE (sorted by first-year price):
  $2.30   connpal.xyz
  $9.73   connpal.com
  $11.99  connpal.app
  $12.12  connpal.dev
TAKEN:
  hintleaf.com, hintleaf.app, ...
PREMIUM (skip unless you love this name):
  $499    wordgrid.com
```

### `check` — single domain, exact price + premium flag

Use `checkDomain` as above but print the full response. Show the user registration, renewal, and first-year cost separately (Porkbun always shows both).

### `register` — **BUYS THE DOMAIN. Costs money.**

**Always confirm with the user before calling `domain/create`.** Show the exact cost (in dollars), the years, and the privacy setting.

```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/create/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{$AUTH,\"years\":1,\"agreeToTerms\":\"yes\",\"whoisPrivacy\":1,\"cost\":\"$COST_USD\"}"
```

Params:
- `years` — integer, default 1
- `agreeToTerms` — must be `"yes"` or `"1"`
- `whoisPrivacy` — `1` (default, free at Porkbun) or `0` (expose registrant info in WHOIS)
- `cost` — **string** of the exact first-year price in dollars (e.g. `"9.73"`); must match the current price or Porkbun rejects

Order of operations:
1. `checkDomain` to get the current price (prices change)
2. Show user: `"Register foo.com for $9.73/year (renewal $11.28/year), WHOIS privacy on. Proceed?"`
3. If yes: call `domain/create` with the exact `cost` from step 1
4. On success, return the order ID and a pointer to `https://porkbun.com/account/domains`

Errors to expect:
- `"We were unable to process..."`  → account email/phone not verified, or no prior registration on the account
- `"Price mismatch"`  → price changed between check and create; re-run check and retry
- `"Insufficient funds"`  → top up account credit at https://porkbun.com/account/credit (Porkbun requires pre-paid credit, not a card-on-file for API buys)

### `list` — owned domains

```bash
curl -sX POST https://api.porkbun.com/api/json/v3/domain/listAll \
  -H 'Content-Type: application/json' \
  -d "{$AUTH,\"includeLabels\":\"yes\"}" | jq '.domains[] | {domain, status, expireDate, autoRenew}'
```

### `ns` — nameservers

**Read**:
```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/getNs/$DOMAIN" \
  -H 'Content-Type: application/json' -d "{$AUTH}" | jq '.ns'
```

**Write** (replace all):
```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/updateNs/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{$AUTH,\"ns\":[\"$NS1\",\"$NS2\"]}"
```

### `ns-cloudflare` — hand DNS over to Cloudflare (automated)

End-to-end: create the Cloudflare zone via API, then push the per-zone nameservers to Porkbun. Requires `CLOUDFLARE_API_TOKEN_ZONE_CREATE` (the *account-owned* token — user tokens cannot create zones). If it's not set, stop and point at `/ro:cloudflare-setup`.

```bash
source ~/.claude/.env

# 1. Create the zone
ZONE_JSON=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ZONE_CREATE" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CLOUDFLARE_ACCOUNT_ID\"},\"type\":\"full\"}")

ok=$(echo "$ZONE_JSON" | jq -r '.success')
if [ "$ok" != "true" ]; then
  echo "$ZONE_JSON" | jq '.errors'
  # Common errors:
  # - 1061 "zone already exists" → zone is already in the account, fetch it with GET /zones?name=$DOMAIN
  # - 10000 "Authentication error" → token lacks Zone Write, re-run /ro:cloudflare-setup
  exit 1
fi

NS1=$(echo "$ZONE_JSON" | jq -r '.result.name_servers[0]')
NS2=$(echo "$ZONE_JSON" | jq -r '.result.name_servers[1]')
ZONE_ID=$(echo "$ZONE_JSON" | jq -r '.result.id')

# 2. Push those NS to Porkbun
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/updateNs/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{$AUTH,\"ns\":[\"$NS1\",\"$NS2\"]}" | jq '{status, message}'

# 3. Tell the user: propagation usually takes 5-60 min for a brand new domain.
#    Activation status can be polled via:
#    curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN_ADMIN" | jq '.result.status'
#    Expect "pending" → "active" once Cloudflare sees the NS change.
```

Verify after a few minutes: `dig NS $DOMAIN +short @1.1.1.1` — should show the two `*.ns.cloudflare.com` hostnames.

**Manual fallback** (if the account-owned token isn't available): have the user add the zone via dashboard → https://dash.cloudflare.com → **Add a site** → `$DOMAIN` → Free plan. The dashboard prints the per-zone NS pair; run `/ro:domain ns $DOMAIN <ns1> <ns2>` with those values.

### `bootstrap` — buy a domain and put it on Cloudflare in one flow

Composes `register` + `ns-cloudflare` + an optional Worker attach step. Use when the user says "buy X and point it at my Worker" — it's the common end-to-end.

```bash
# 1. check + confirm + register (see `register` subcommand)
# 2. ns-cloudflare (see above) — creates zone + swaps NS
# 3. if --worker <name> passed: add two routes on the Worker
#    for $DOMAIN and www.$DOMAIN via wrangler.jsonc, and run `wrangler deploy`.
#    Requires CLOUDFLARE_API_TOKEN_ADMIN for the custom_domain attach.
```

Report at the end: zone ID, nameservers, Worker bindings (if any), and whether the zone is `pending` or already `active`. Remind the user that until the zone is active, HTTPS on the new domain won't serve traffic — but it usually flips within minutes for a brand-new domain (slower for moves from an existing registrar-hosted DNS).

### `forward` — URL forwarding

Porkbun can redirect a bare domain to a URL (useful for parking before you deploy something). Survives without setting up DNS or a server.

```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/domain/addUrlForward/$DOMAIN" \
  -H 'Content-Type: application/json' \
  -d "{$AUTH,\"subdomain\":\"\",\"location\":\"$TARGET_URL\",\"type\":\"temporary\",\"includePath\":\"no\",\"wildcard\":\"yes\"}"
```

Use `"type":"permanent"` for a 301; `"temporary"` for 302.

### `dns-list` — DNS records (only useful if Porkbun is your NS)

```bash
curl -sX POST "https://api.porkbun.com/api/json/v3/dns/retrieve/$DOMAIN" \
  -H 'Content-Type: application/json' -d "{$AUTH}" | jq '.records'
```

If Cloudflare is the nameserver, use `/ro:cloudflare-dns list` instead.

## Quick availability without an account

If the user doesn't yet have Porkbun credentials, fall back to `whois` or `dig` for a rough first pass:

```bash
whois example.com | head -5          # "No match" / "NOT FOUND" => likely available
dig NS example.com +short            # empty output => likely available (but some domains have no NS)
```

These give a signal, not a guarantee. Premium / reserved names can show as available in WHOIS but be un-buyable at normal prices. Always verify with `check` once keys are in place.

## Safety

- **`register` spends real money.** Never call it without an explicit user "yes" and showing the exact cost. Don't auto-retry on failure (the user may not want to re-attempt at a new price).
- **`ns` / `updateNs` can break email and websites.** Show the current NS before overwriting, warn on production domains, and recommend lowering TTLs to 300 before the switch if the domain is in active use.
- Porkbun bills from account credit, not a card. A failed register for `Insufficient funds` means the user needs to pre-pay at https://porkbun.com/account/credit. Don't try to top up from the skill, it's manual.
- Never log the raw `PORKBUN_SECRET_API_KEY`. When echoing a curl command for the user to re-run, replace the key with `$PORKBUN_SECRET_API_KEY`.
- **First-time users**: remember the "at least one prior registration" rule. If `domain/create` fails immediately after account creation, the fix is to buy one domain through the web UI first.

## Recommended post-purchase flow

1. `/ro:domain register mydomain.com` — buy
2. `/ro:domain ns-cloudflare mydomain.com` — create CF zone + move DNS
3. `/ro:cloudflare-dns add @ A <ip>` or whatever records you need
4. `/ro:cf-ship --domain mydomain.com` (if deploying a Worker) — attach custom domain

Or collapse steps 1-2 into `/ro:domain bootstrap mydomain.com --worker my-worker`.

## Cloudflare token requirements

`ns-cloudflare` and `bootstrap` need **two** Cloudflare tokens because of how Cloudflare's permission model splits up — zone *creation* is not available on user tokens, only account-owned tokens.

- `CLOUDFLARE_API_TOKEN_ZONE_CREATE` (account-owned, prefix `cfat_`) — for creating the zone
- `CLOUDFLARE_API_TOKEN_ADMIN` (user, prefix `cfut_`) — for DNS, Worker attach, redirect rules
- `CLOUDFLARE_ACCOUNT_ID` — used in the zone-create payload

If any are missing, run `/ro:cloudflare-setup` first. That skill walks the user through minting both tokens with the right scopes.

## See also

- `/ro:cloudflare-setup` — one-time Cloudflare token minting (prereq for `ns-cloudflare` / `bootstrap`)
- `/ro:cloudflare-dns` — DNS management once nameservers are on Cloudflare
- `/ro:cf-ship` — deploy a Worker with a custom domain
- https://porkbun.com/api/json/v3/documentation — full API reference
