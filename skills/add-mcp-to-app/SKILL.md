---
name: add-mcp-to-app
description: Expose an existing TanStack Start + Cloudflare Workers app as an MCP server that MCP-speaking agents (Claude Code, Codex, Cursor, anything that talks the Model Context Protocol) can install in one command. Adds the OAuth 2.1 authorization-server routes (.well-known discovery, /oauth/authorize with auth-code + PKCE, /oauth/token, /oauth/register for Dynamic Client Registration), an /api/mcp handler that accepts both Bearer-token PATs and OAuth access tokens, and a sibling Claude Code plugin repo (<app>-plugin) that ships .mcp.json + a cross-agent setup skill so install is `/plugin marketplace add <org>/<app>-plugin` for everyone. Use when user wants to ship an MCP server on their existing app, expose their app to agents, make their app installable as a plugin, add an MCP layer, distribute as a Claude Code plugin, or share their app's tools with Claude / Codex / Cursor.
category: agent-tooling
argument-hint: [--app-repo <path>] [--plugin-repo <path>] [--org <github-org>] [--mcp-path /api/mcp] [--clerk | --workos | --better-auth] [--skip-oauth | --skip-plugin]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(wrangler *) Bash(git *) Bash(gh *) Bash(mkdir *) Bash(curl *) Bash(npx *) Read Write Edit Skill
---

# Add MCP to an existing app

Take an app you already shipped (TanStack Start on Cloudflare Workers) and turn it into a one-command install for any MCP-speaking agent. The reference implementation this skill was distilled from is [Simplicity-Labs/dataforce](https://github.com/Simplicity-Labs/dataforce) (the app) + [Simplicity-Labs/dataforce-plugin](https://github.com/Simplicity-Labs/dataforce-plugin) (the plugin), shipped on 2026-05-14.

The pattern this skill scaffolds:

```
Your agent (Claude Code / Codex / Cursor) ── stdio ──► npx -y mcp-remote ──► HTTPS ──► https://<your-app>/api/mcp
                                                            │
                                                            └── browser OAuth on first run (Clerk → your app → mcp-remote → agent)
```

`mcp-remote` is the cross-agent OAuth client. The same `npx -y mcp-remote <url>` command works in any MCP host, which is why the **same plugin repo serves every agent**. Two-repo distribution decouples the public plugin manifest from the (often private) app codebase.

## When to use this skill

Use when:
- You have a TanStack Start app on Cloudflare Workers (or close to it) with internal data worth exposing as MCP tools.
- You want non-engineers (or your future self on another machine) to install it without pasting tokens.
- Distribution should ride GitHub plugin marketplaces, not a one-off `claude mcp add` per teammate.

Skip when:
- The MCP server has a single human user on a single machine — `/ro:new-mcp-server <name> --stdio` is the right tool (local stdio, no OAuth machinery).
- The app is not yet deployed or not yet on Workers — finish `/ro:new-tanstack-app` and `/ro:cf-ship` first; this skill assumes a working production URL.
- You want only a bearer-token PAT install path — that's a 30-line `/api/mcp` route, no OAuth backend needed; this skill is overkill.

## Prerequisites

- An existing TanStack Start + Cloudflare Workers app, deployed and reachable on a public URL.
- Drizzle + D1 (or Postgres via Neon) already wired — OAuth needs durable storage for refresh tokens, authorization codes, and PKCE challenges.
- A user-identity IdP already wired (Clerk by default, WorkOS or Better Auth also fine). This skill makes **your app** the OAuth authorization server for its own API; the IdP underneath authenticates the human at the consent step. Without an IdP, run `/ro:clerk install` first.
- `gh` CLI authed against the GitHub org that will host both repos.
- For the plugin repo: a GitHub org or username that can host a public repo named `<app-name>-plugin`.

## Decision tree

```
Existing TanStack Start + CF Workers app?
├── No → /ro:new-tanstack-app first, then come back
└── Yes
    ├── Already has /api/mcp handler?
    │   ├── No → this skill scaffolds the handler (step B)
    │   └── Yes → skip step B, extend handler to accept OAuth tokens
    ├── Already has /.well-known/oauth-authorization-server?
    │   ├── No → this skill adds the full OAuth backend (step A)
    │   └── Yes → diff the discovery doc, ensure it advertises authorization_code grant
    └── Plugin repo (<app>-plugin) on GitHub?
        ├── No → this skill scaffolds and publishes (step C)
        └── Yes → updates .mcp.json + setup-skill in place (step D)
```

## Process

The skill walks four steps in order, prompting via AskUserQuestion before each structural change. Steps A and B touch the app repo; steps C and D touch (or create) the plugin repo. The user can opt out of any step with the corresponding `--skip-*` flag.

### Step A — Add the OAuth authorization-server backend to the app repo

This is the load-bearing piece. `mcp-remote` defaults to OAuth 2.1 auth-code + PKCE (not device flow), so the app needs:

1. **Discovery doc** at `/.well-known/oauth-authorization-server` advertising the authorization, token, and registration endpoints plus supported grant types and PKCE methods.
2. **Authorization endpoint** at `/oauth/authorize` — a Clerk-gated (or WorkOS / Better Auth-gated) consent page where the human clicks Allow / Deny.
3. **Server handler** at `/api/oauth/authorize` — issues authorization codes server-side after consent, persists `client_id` + `redirect_uri` + `code_challenge` + `code_challenge_method` to a new `oauth_authorization_code` table.
4. **Token endpoint** at `/api/oauth/token` — multiplexes existing grant types (`refresh_token`, `client_credentials`, `device_code` if you have it) with the new `authorization_code` grant, validating the PKCE verifier on exchange.
5. **Dynamic Client Registration** at `/oauth/register` — POST endpoint that returns a `client_id` for any client that registers, so `mcp-remote` can self-register on first use rather than requiring a hand-shared client ID.

**AskUserQuestion before scaffolding:**

> "About to add five routes (`/.well-known/oauth-authorization-server`, `/oauth/authorize`, `/api/oauth/authorize`, `/api/oauth/token`, `/oauth/register`) and one Drizzle migration (`oauth_authorization_code` table). Proceed?"

If yes, base the implementation on the dataforce reference. The shape that worked:

```
src/lib/oauth.ts                       <- pkceS256Challenge, startAuthorizationCode,
                                          exchangeAuthorizationCode helpers
src/routes/api/oauth.token.ts          <- token endpoint, multiplexes grant types
src/routes/api/oauth.authorize.ts      <- server handler, GET returns client info,
                                          POST records consent + redirects with code
src/routes/oauth.authorize.tsx         <- consent page (gated by Clerk auth)
src/routes/api/oauth.register.ts       <- DCR endpoint, returns minted client_id
src/routes/.well-known/oauth-authorization-server.ts  <- discovery doc
drizzle/NNNN_<name>.sql                <- oauth_authorization_code table
src/db/schema.ts                       <- oauthAuthorizationCode table declaration
```

Reference commit: dataforce PR [#142](https://github.com/Simplicity-Labs/dataforce/pull/142) (auth-code + PKCE on `/oauth/authorize`), merged 2026-05-14.

Key implementation notes:

- The discovery doc must advertise `code_challenge_methods_supported: ["S256"]`. `mcp-remote` does S256, not plain.
- The `oauth_authorization_code` row stores `code_challenge`, `code_challenge_method`, `client_id`, `redirect_uri`, `scope`, `user_id` (from Clerk session), and an expiry of 10 minutes max. Delete on exchange. Single-use.
- DCR is required for the public-client install path. Without it, `mcp-remote` has nothing to register and fails before the consent step.
- After scaffolding, generate + apply the migration: `pnpm drizzle-kit generate && wrangler d1 migrations apply <db> --local` (and `--remote` after testing).

### Step B — Add the /api/mcp handler (if not present)

If the app does not already expose `/api/mcp`, scaffold it. The handler MUST accept both:

1. **Bearer-token PATs** (for power users who want to bypass OAuth). Look up the token in the existing `personal_access_token` table.
2. **OAuth access tokens** (the default install path via `mcp-remote`). Verify the token against whatever the OAuth backend issued (JWT or DB-backed opaque token).

**AskUserQuestion before scaffolding:**

> "Scaffold a new `/api/mcp` handler? If you already have one, choose 'extend existing' so I add OAuth-token validation alongside whatever you already have."

If scaffolding from scratch, lean on `cloudflare:build-mcp` (load via the `Skill` tool) for the McpAgent boilerplate, then layer auth on top. Tools, resources, and prompts are app-specific; this skill does not invent them. It just wires the handler.

### Step C — Scaffold the sibling plugin repo

The plugin repo is intentionally a separate GitHub repo from the app. Why:

- The app repo is often private; the plugin manifest is public.
- The plugin manifest changes on a different cadence than the app (rare).
- Install path is a clean `/plugin marketplace add <org>/<app-name>-plugin` URL.

**AskUserQuestion before creating:**

> "Create a new repo at `<org>/<app-name>-plugin` on GitHub and scaffold the plugin? Or point me at an existing plugin repo path?"

If new, scaffold this exact shape:

```
<app-name>-plugin/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── .mcp.json
├── skills/
│   └── <app-name>-setup/
│       └── SKILL.md
├── LICENSE
└── README.md
```

`.mcp.json` (the cross-agent install command — NO tokens, OAuth handles auth):

```json
{
  "mcpServers": {
    "<app-name>": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://<your-app-host>/api/mcp"
      ]
    }
  }
}
```

`.claude-plugin/plugin.json` — declares the plugin, its version, its keywords. Set `homepage` to the app's public URL and `repository` to the plugin repo's GitHub URL.

`.claude-plugin/marketplace.json` — declares this repo IS the marketplace, with the single plugin inside.

`skills/<app-name>-setup/SKILL.md` — the **cross-agent configurator**, the piece that makes this pattern pay off beyond Claude Code. The skill:

1. Detects which agents are installed locally (`~/.claude.json`, `~/.codex/config.toml`, `~/.cursor/mcp.json`).
2. Pre-selects the detected ones in an AskUserQuestion confirm step.
3. Writes the right config to each idempotently. Backs up before writing.
4. Verifies `npx -y mcp-remote --help` works and the MCP endpoint responds (401 is fine — that's the OAuth prompt).
5. Prints next steps (restart agent, trigger a tool call, browser will pop on first OAuth).

The dataforce-setup skill ([source](https://github.com/Simplicity-Labs/dataforce-plugin/blob/main/skills/dataforce-setup/SKILL.md)) is the working reference — copy the structure, substitute the app name and MCP URL.

**Crucially**: the setup skill does NOT write a Claude Code MCP config when the plugin is installed via marketplace — that's already handled by `.mcp.json`. Writing it again double-registers the server. Skip with a note.

### Step D — Publish the plugin repo

After scaffolding:

```bash
cd <plugin-repo>
git init && git add -A && git commit -m "✨ feat: scaffold <app-name>-plugin (Claude Code marketplace)"
gh repo create <org>/<app-name>-plugin --public --source=. --remote=origin --push
```

**AskUserQuestion before publishing:**

> "Push the plugin repo to `<org>/<app-name>-plugin` as **public**? It needs to be public for `/plugin marketplace add` to work without auth."

After push, the install command is:

```
/plugin marketplace add <org>/<app-name>-plugin
/plugin install <app-name>@<app-name>-plugin
```

For Codex / Cursor / anything else, `/<app-name>-setup` (the bundled skill) wires it.

## Verification

After all four steps, run end-to-end:

1. **OAuth discovery**: `curl https://<your-app-host>/.well-known/oauth-authorization-server` — should return JSON with the four endpoints and `code_challenge_methods_supported: ["S256"]`.
2. **mcp-remote dry run**: `npx -y mcp-remote https://<your-app-host>/api/mcp --version` — should print a version and exit without erroring on the URL.
3. **Plugin install on a fresh machine** (the real test): `/plugin marketplace add <org>/<app-name>-plugin` then `/plugin install <app-name>@<app-name>-plugin`. First tool call should pop a browser, Clerk login → consent → token issued → tool returns data.

If the browser pop fails, the OAuth backend is wrong. The discovery doc + Step A are where the bug is. The plugin side is purely declarative.

## Output summary

After running, print:

- App repo: routes added, migration applied (db name + migration filename), commit SHAs
- Plugin repo: URL, install command, contents of `.mcp.json`
- Setup skill name (e.g. `/<app-name>-setup`)
- A copy-pastable install snippet to share with teammates

## Safety

- Never hardcode the OAuth client secret anywhere in the plugin repo. Public clients (`mcp-remote`) use PKCE precisely so a client secret isn't needed.
- The `<app-name>-setup` skill MUST NOT touch `~/.mcp-auth/` — tokens live there, managed by `mcp-remote` itself. The skill only writes the *command* that invokes mcp-remote.
- Backup every config file before writing. Pattern: `<path>.bak.<unix-timestamp>`.
- If the app's `/.well-known/oauth-authorization-server` already exists, diff it before overwriting. Some apps stub the discovery doc before implementing the endpoints (the dataforce path: the doc landed in an earlier PR before #142 finished the implementation).

## Anti-patterns it guards against

- Shipping a bearer-token-only install path because OAuth feels heavy. It is heavier upfront, but it scales to "non-engineers can install this" and that's the whole point.
- Writing one config-write skill per agent (Claude / Codex / Cursor). One skill, one detect step, one write loop per detected agent. `mcp-remote` is what unifies them.
- Putting the `.mcp.json` in the app repo. Decouple. The plugin repo's whole job is distribution; the app repo's whole job is the API.
- Forgetting Dynamic Client Registration. Without `/oauth/register`, the install dies before the consent page on a fresh machine.
- Using `device_code` grant alone. `mcp-remote` defaults to auth-code + PKCE; device flow is a fallback for environments without a browser (CI, headless), not the primary path.
- Writing a Claude Code MCP config from the setup skill when the plugin manifest already handles it. Double-registers the server.

## See also

- `/ro:new-mcp-server` — scaffold a brand-new MCP server (this skill is for adding MCP to an *existing* app)
- `/ro:clerk` (default IdP), `/ro:workos`, `/ro:better-auth` — user-identity layer underneath the OAuth authorization server
- `/ro:new-tanstack-app` — the upstream scaffold this skill assumes
- `/ro:cf-ship` — deploy the app repo after OAuth routes are added
- `cloudflare:build-mcp` (Cloudflare plugin) — McpAgent boilerplate for the `/api/mcp` handler
- skill-lab pattern page `patterns/mcp-on-cf-workers-with-oauth.md` for the architectural rationale
- Reference impl: [Simplicity-Labs/dataforce](https://github.com/Simplicity-Labs/dataforce) + [Simplicity-Labs/dataforce-plugin](https://github.com/Simplicity-Labs/dataforce-plugin), dataforce PR [#142](https://github.com/Simplicity-Labs/dataforce/pull/142)
