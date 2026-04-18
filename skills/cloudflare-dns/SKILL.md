---
name: cloudflare-dns
description: Manage Cloudflare DNS records via the API — add, update, or delete subdomains (A, AAAA, CNAME, TXT, MX). Use when user wants to add a subdomain, point a DNS record, create/update/delete DNS entries on Cloudflare, or set up a custom domain for a hosted app (Fly, Vercel, Render, etc.).
category: deployment
argument-hint: <subcommand> [args]
allowed-tools: Bash(curl *) Bash(jq *) Read Write Edit
---

# Cloudflare DNS

Manage DNS records on Cloudflare via the API v4. Typical use: pointing a subdomain at a Fly.io / Vercel / Render hostname.

## Usage

```
/ro:cloudflare-dns add api.myapp.com CNAME myapp.fly.dev --proxied
/ro:cloudflare-dns list myapp.com
/ro:cloudflare-dns update <record-id> <zone-id> --content new-target.fly.dev
/ro:cloudflare-dns delete api.myapp.com
```

## Process

### 1. Load credentials

Check in order for `CLOUDFLARE_API_TOKEN` (required) and optionally `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_ACCOUNT_ID`:
1. `${CLAUDE_PLUGIN_DATA}/.env` (preferred — plugin-wide, survives updates)
2. `~/.config/ro/.env`
3. Project root `.env`
4. Shell env var

Expected shape:
```
CLOUDFLARE_API_TOKEN=...                      # required
CLOUDFLARE_ZONE_ID=...                        # optional: skips lookup in step 2
CLOUDFLARE_ACCOUNT_ID=...                     # optional: needed for tunnels/workers
```

If token missing: direct user to https://dash.cloudflare.com/profile/api-tokens → **Create Token** → template "Edit zone DNS" (scopes: `Zone:DNS:Edit`, `Zone:Zone:Read`; add `Tunnel:Edit` if you also plan to use tunnels). Save:

```bash
mkdir -p "$CLAUDE_PLUGIN_DATA" && chmod 700 "$CLAUDE_PLUGIN_DATA"
cat >> "$CLAUDE_PLUGIN_DATA/.env" <<'EOF'
CLOUDFLARE_API_TOKEN=...
CLOUDFLARE_ZONE_ID=...
CLOUDFLARE_ACCOUNT_ID=...
EOF
chmod 600 "$CLAUDE_PLUGIN_DATA/.env"
```

### 2. Resolve zone ID

If `CLOUDFLARE_ZONE_ID` is already in the env **and** matches the apex of the record you're editing, skip the lookup. Otherwise resolve it:

```bash
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=myapp.com" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result[0].id')
```

Quick sanity check when using the env zone ID:
```bash
curl -s "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result.name'
```

If `null`: the domain isn't on Cloudflare or the token lacks `Zone:Zone:Read`. Stop and tell the user.

### 3. Perform the operation

Base URL: `https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records`

**Add** (POST):
```bash
curl -s -X POST "$BASE" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"CNAME","name":"api","content":"myapp.fly.dev","ttl":1,"proxied":true}'
```
- `ttl: 1` = auto
- `proxied: true` = orange cloud (Cloudflare in front). Use `false` for Fly.io custom domains that need direct TLS termination on Fly.

**List** (GET): `curl -s "$BASE?name=api.myapp.com" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"` — returns record id + current values.

**Update** (PATCH `$BASE/<record_id>`): send only changed fields.

**Delete** (DELETE `$BASE/<record_id>`): **always confirm with the user first** — deleting DNS can drop production traffic.

### 4. Verify

After a write, re-fetch the record and show the user the final `name`, `type`, `content`, `proxied`, `ttl`. Mention propagation: Cloudflare is fast (~seconds) but downstream resolvers may cache for up to TTL.

## Fly.io custom domain recipe

When chaining with `/ro:fly-deploy`:

1. `flyctl certs create api.myapp.com -a <app>` → fly returns required DNS records
2. Add the **acme challenge** CNAME (usually `_acme-challenge.api.myapp.com` → `<app>.fly.dev`) with `proxied: false`
3. Add the main `api.myapp.com` record as either:
   - **CNAME** → `<app>.fly.dev` (proxied: false — let Fly terminate TLS), OR
   - **A/AAAA** → fly shared IPs from `flyctl ips list -a <app>` (proxied: true OK)
4. `flyctl certs show api.myapp.com -a <app>` — wait for `Issued` status

## Error handling

- **401/403**: Token invalid or missing `Zone:DNS:Edit` scope
- **`errors[].code: 81057`**: Record already exists — list first, then PATCH instead of POST
- **`errors[].code: 1004`**: Bad DNS content (e.g. CNAME pointing to raw IP)
- **`success: false`**: Surface the `errors[]` array verbatim to the user

## Safety

- Never delete records without explicit user confirmation
- For prod zones, show the existing record value before overwriting
- Never log the `CLOUDFLARE_API_TOKEN` value
