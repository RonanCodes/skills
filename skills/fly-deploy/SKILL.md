---
name: fly-deploy
description: Deploy and manage apps on Fly.io via the flyctl CLI. Use when user wants to deploy, ship, launch, release, or manage a Fly.io app — including `fly deploy`, `fly status`, `fly logs`, `fly secrets`, `fly certs`, scaling, and setting up custom domains for Dockerised frontend/backend apps.
category: deployment
argument-hint: <subcommand> [args]
allowed-tools: Bash(flyctl *) Bash(fly *) Bash(curl *) Read Write Edit
---

# Fly.io Deploy

Ship Docker containers to Fly.io using `flyctl`. Covers launch, deploy, status, logs, secrets, scaling, and custom domains.

## Usage

```
/ro:fly-deploy launch                    # first-time scaffold for this repo
/ro:fly-deploy deploy                    # build + push + release
/ro:fly-deploy status                    # current machines + health
/ro:fly-deploy logs [--tail]
/ro:fly-deploy secrets set KEY=value ...
/ro:fly-deploy certs add api.myapp.com   # custom domain (pairs with /ro:cloudflare-dns)
```

## Prerequisites

- `flyctl` installed — if missing: `brew install flyctl` (macOS) or `curl -L https://fly.io/install.sh | sh`
- Authenticated — check `flyctl auth whoami`. If not authed, use one of:
  - `flyctl auth login` (browser, interactive)
  - **Org token (preferred for agentic use)**: set `FLY_ORG_TOKEN` in `~/.claude/.env`. Generate at https://fly.io/dashboard → your org → Access Tokens → Create Org Token
  - **Personal access token (wider scope, avoid)**: set `FLY_API_TOKEN` in `~/.claude/.env`. Generate at https://fly.io/user/personal_access_tokens
- A `Dockerfile` in the project (or use `flyctl launch` to generate one)

### Token scope (important)

This skill is designed around an **organization-scoped token** (`FLY_ORG_TOKEN`) — lower blast radius than a personal access token.

| Capability | Org token | Personal token |
|---|---|---|
| Deploy, read, write, manage secrets within **its own org** | ✅ | ✅ |
| Access multiple orgs | ❌ (token is pinned to one org) | ✅ |
| Create new orgs / manage billing | ❌ | ✅ |
| Appropriate for agent automation | ✅ | ⚠️ overly broad |

`flyctl` natively reads `FLY_API_TOKEN` only, so the skill shadows it at invocation:

```bash
export FLY_API_TOKEN="${FLY_ORG_TOKEN:-${FLY_API_TOKEN}}"
```

The skill verifies the token before any destructive-ish command by running `flyctl auth whoami` and reporting `token: Organization Token` so the user can confirm they're about to act with the scope they expect.

## Process

### First-time launch

```bash
flyctl launch --no-deploy          # generates fly.toml, asks region + org
```

Review the generated `fly.toml` before deploying:
- `app` — globally unique name (becomes `<app>.fly.dev`)
- `primary_region` — closest to users (e.g. `lhr`, `iad`, `sjc`)
- `[http_service]` — `internal_port` must match the container's listen port
- `[[vm]]` — size (default `shared-cpu-1x` / 256MB — bump for FE builds with SSR)

Then: `flyctl deploy`.

### Subsequent deploys

```bash
flyctl deploy --remote-only        # build on Fly's builders (no local Docker needed)
```

Flags to know:
- `--strategy immediate` — replace all machines at once (dev only)
- `--strategy rolling` — default, zero downtime
- `--ha=false` — single machine only (cheaper for staging)
- `--dockerfile <path>` — non-default Dockerfile
- `--build-arg KEY=value` — build-time args

### Infrastructure docs (post-first-deploy)

After a successful deploy, if `docs/infrastructure/` is absent (first deploy) or the deploy changed apps/volumes/secrets/machines, run `/ro:infra-docs` to generate or refresh the living architecture docs (live resource inventory, C4 + sequence diagrams, security model, provisioning runbook). It discovers live Fly state via `flyctl`. Idempotent, so re-run after notable deploys.

### Status & logs

```bash
flyctl status -a <app>             # machine list, regions, health
flyctl logs -a <app>               # stream logs
flyctl releases -a <app>           # deploy history
flyctl ssh console -a <app>        # shell into a running machine
```

### Secrets

Secrets are baked into the container env at runtime (restarts machines):

```bash
flyctl secrets set DATABASE_URL=postgres://... STRIPE_KEY=sk_... -a <app>
flyctl secrets list -a <app>
flyctl secrets unset OLD_VAR -a <app>
```

Never paste secrets into `fly.toml` — use `flyctl secrets set`.

### Custom domains (subdomain on Cloudflare)

```bash
flyctl certs create api.myapp.com -a <app>
flyctl certs show api.myapp.com -a <app>     # shows required DNS + validation status
flyctl ips list -a <app>                     # A/AAAA targets if you prefer A over CNAME
```

Then chain with **`/ro:cloudflare-dns`** to add the records. Poll `certs show` until status is `Issued` (usually 30s–2min).

### Scaling

```bash
flyctl scale count 2 -a <app>             # horizontal (machines)
flyctl scale vm shared-cpu-2x -a <app>    # vertical (CPU/RAM preset)
flyctl scale memory 1024 -a <app>         # memory only
```

## Cost sizing cheatsheet

`shared-cpu-1x` machine pricing (approx, Amsterdam tier — other regions have small multipliers):

| Memory | $/month (always on) | $/hour |
|--------|---------------------|--------|
| 256MB  | $2.02 | $0.0028 |
| 512MB  | $3.32 | $0.0046 |
| 1GB    | $5.92 | $0.0082 |
| 2GB    | $11.11 | $0.0154 |

- **Stopped machine**: rootfs only — ~$0.15/GB-month of image size. For a 65MB image ≈ $0.01/mo.
- **Volume**: $0.15/GB-month. **Minimum size is 1GB** — you cannot shrink below it, and `fly volumes extend` only goes up. Plan sizes carefully.
- **Scale to zero** (`auto_stop_machines="suspend"` + `min_machines_running=0`) → you only pay compute while serving. A personal tool typically costs $0.30–$1/mo all-in.

### `suspend` vs `stop` (both free of extra cost)

| Mode | Cold start | When to use |
|------|-----------|-------------|
| `suspend` | ~200ms (keeps memory snapshot) | **Default for most apps** — UX win at zero cost |
| `stop` | ~1-3s | Long-idle apps or edge cases where snapshots misbehave |

Live pricing: https://fly.io/docs/about/pricing/

## Common failure modes

- **"App not found"** — wrong `-a`, or token is pinned to a different org than the app lives in. Run `flyctl orgs list` to confirm the token's org. Org tokens cannot reach apps in other orgs.
- **"You must be authenticated"** via API/GraphQL — `FLY_API_TOKEN` isn't shadowed from `FLY_ORG_TOKEN`. Check with `echo "${FLY_API_TOKEN:-unset}"`.
- **Build OOM** — bump builder with `flyctl deploy --vm-memory 2048` or upgrade machine size
- **Healthcheck fails** — `internal_port` in `fly.toml` doesn't match what the container listens on
- **Cert stuck in `awaiting_configuration`** — DNS record missing or wrong proxied flag (Fly needs unproxied / grey-cloud on Cloudflare for TLS termination)

## Safety

- `flyctl apps destroy` and `flyctl machine destroy` are irreversible — always confirm with the user first
- `flyctl deploy` to a prod app: show the user the current release and the new image tag before shipping
- Never commit `fly.toml` with hardcoded secrets — use `[env]` for non-secret config only

## See also

- `/ro:cloudflare-dns` — add the subdomain after `certs create`
- Fly docs: https://fly.io/docs — use context7 if fetching current syntax
