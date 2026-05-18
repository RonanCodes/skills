---
name: new-mcp-server
description: Scaffold a new MCP server (Model Context Protocol). Two transports — hosted (Cloudflare Workers via McpAgent) and local (stdio). Wires tools, resources, prompts with Zod schemas, optional WorkOS auth for hosted multi-tenant servers, optional /.well-known/mcp/server-card.json for the in-flight server-card spec, and the MCP Inspector for local dev. Use when user wants to create an MCP server, new MCP server, scaffold an MCP server, build an MCP server, MCP server skeleton, or publish an MCP server.
category: agent-tooling
argument-hint: [<server-name>] [--hosted | --stdio] [--with-auth=workos] [--with-card]
allowed-tools: Bash(pnpm *) Bash(pnpx *) Bash(npm *) Bash(npx *) Bash(wrangler *) Bash(git *) Bash(mkdir *) Read Write Edit Skill
---

# New MCP Server

Scaffold a new MCP server using the user's conventions. Two transports:

- **Hosted (Workers via McpAgent)**: shareable, multi-tenant, deployed at a public URL. Compose with the Cloudflare plugin's `cloudflare:build-mcp` skill rather than re-implementing it. This skill is the opinionated wrapper that adds auth, observability, server-card scaffolding, and the user's project conventions.
- **Local (stdio)**: personal-use server consumed by Claude Code, Cursor, Continue. Just `@modelcontextprotocol/sdk` over stdio.

Default is `--stdio` unless the server is multi-tenant.

## Usage

```
/ro:new-mcp-server my-server                     # interactive picker (asks transport)
/ro:new-mcp-server my-server --stdio             # local stdio server
/ro:new-mcp-server my-server --hosted            # Cloudflare Workers + McpAgent
/ro:new-mcp-server my-server --hosted --with-auth=workos
/ro:new-mcp-server my-server --hosted --with-card        # also serve /.well-known/mcp/server-card.json
```

## Decision tree

```
Will more than one person use it (or you across machines)?
├── No → --stdio (run locally, install via npx)
└── Yes
    ├── Does it need user-specific data or per-user auth?
    │   ├── No  → --hosted (public, anonymous, rate-limited)
    │   └── Yes → --hosted --with-auth=workos (multi-tenant)
    └── Want it discoverable for AI clients to enumerate?
        └── Add --with-card (opt-in, schema is Draft, see below)
```

## Prerequisites

- Node 22 + pnpm
- For `--hosted`: `wrangler` (`pnpm add -g wrangler`), Cloudflare account, the `cloudflare:build-mcp` skill from the Cloudflare plugin reachable via `Skill` tool
- For `--hosted --with-auth=workos`: a WorkOS account (the auth handler dispatches to `/ro:workos`)

## Project shape

Both transports share these conventions:

```
my-server/
├── package.json          # name, mcp keyword, bin (stdio) or build script (hosted)
├── tsconfig.json
├── src/
│   ├── server.ts         # McpServer instance + tool/resource/prompt registrations
│   ├── tools/            # one file per tool (Zod schema + handler colocated)
│   ├── resources/        # one file per resource
│   └── prompts/          # one file per prompt
└── README.md             # how to install + an example tool call
```

Hosted variant adds `wrangler.toml`, `src/index.ts` (Workers entry), and optionally `src/well-known.ts`.

Stdio variant adds `bin/cli.ts` (the entry that wires `StdioServerTransport`).

## --stdio (local)

### 1. Scaffold

```bash
mkdir my-server && cd my-server
pnpm init
pnpm add @modelcontextprotocol/sdk zod
pnpm add -D typescript tsx @types/node
```

### 1a. Supply-chain hardening → `/ro:harden-npm`

```bash
/ro:harden-npm
```

MCP servers often get published to npm, so they need especially tight supply-chain controls (a poisoned MCP server gets executed inside Claude Code with full filesystem access). See `llm-wiki-security/wiki/playbooks/npm-supply-chain-hardening.md`.

`package.json`:

```json
{
  "name": "my-mcp-server",
  "version": "0.1.0",
  "type": "module",
  "bin": { "my-mcp-server": "./dist/cli.js" },
  "keywords": ["mcp", "modelcontextprotocol"],
  "scripts": {
    "dev": "npx @modelcontextprotocol/inspector tsx src/cli.ts",
    "build": "tsc",
    "start": "node dist/cli.js"
  }
}
```

The `mcp` and `modelcontextprotocol` keywords are how clients discover the server on npm.

### 2. Server module, `src/server.ts`

```ts
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

export function createServer() {
  const server = new McpServer({ name: 'my-mcp-server', version: '0.1.0' });

  server.registerTool(
    'hello',
    {
      title: 'Say hello',
      description: 'Return a greeting for a given name',
      inputSchema: z.object({ name: z.string() }),
      annotations: { readOnlyHint: true, idempotentHint: true },
    },
    async ({ name }) => ({
      content: [{ type: 'text', text: `Hello, ${name}!` }],
    }),
  );

  return server;
}
```

The MCP TypeScript SDK requires `inputSchema` to be wrapped with `z.object()` (Zod v4); raw shapes from v1 of the SDK no longer work. Note that for `--hosted` (McpAgent in Cloudflare's `agents` SDK), the McpAgent wrapper still accepts the v1 raw-shape form for backward compatibility, but new code should use `z.object()` everywhere for consistency.

### 3. Stdio entry, `src/cli.ts`

```ts
#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createServer } from './server.js';

async function main() {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

### 4. Local dev with the Inspector

```bash
pnpm dev
```

The MCP Inspector opens a UI at `http://localhost:5173`, connects to your server over stdio, lets you call tools and inspect resources without wiring a real client.

### 5. Install in Claude Code

After `pnpm build`:

```bash
claude mcp add my-mcp-server -- node /absolute/path/to/dist/cli.js
```

Or publish to npm (`pnpm publish`) and consumers add via `npx`:

```bash
claude mcp add my-mcp-server -- npx -y my-mcp-server
```

## --hosted (Cloudflare Workers via McpAgent)

For the canonical Cloudflare McpAgent flow, dispatch first:

```
Skill cloudflare:build-mcp
```

Read its scaffold steps, then layer the user's conventions on top. The differences from the bare Cloudflare scaffold:

### 1. Use pnpm, not npm

Match the rest of the user's stack. After `npx create-cloudflare@latest --template cloudflare/agents-starter`, swap to pnpm:

```bash
rm -rf node_modules package-lock.json
pnpm install
```

### 2. Enable Workers Observability in `wrangler.toml`

```toml
[observability]
enabled = true
head_sampling_rate = 1
```

200K events/day free, no separate setup. This is non-negotiable for a public MCP server you cannot debug in person.

### 3. Tool registration

Same `McpServer` API as stdio, registered inside `init()` of your `McpAgent` subclass. Example from the Cloudflare scaffold annotated for the user's conventions:

```ts
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { McpAgent } from 'agents/mcp';
import { z } from 'zod';

export class MyMCP extends McpAgent<Env, {}, {}> {
  server = new McpServer({ name: 'my-server', version: '0.1.0' });

  async init() {
    this.server.registerTool(
      'fetch_user',
      {
        description: 'Look up a user by ID',
        inputSchema: z.object({ id: z.string() }),
      },
      async ({ id }) => {
        const user = await this.env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();
        return {
          content: [{ type: 'text', text: JSON.stringify(user) }],
          structuredContent: user,
        };
      },
    );
  }
}

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    return MyMCP.serve('/mcp', { binding: 'MyMCP' }).fetch(request, env, ctx);
  },
};
```

`MyMCP.serve('/mcp')` is the Streamable HTTP transport (recommended). `serveSSE('/sse')` is deprecated.

### 4. Deploy + register

```bash
wrangler deploy
```

Consumers add the public URL to their `mcp.json`:

```json
{
  "mcpServers": {
    "my-server": { "url": "https://my-server.<account>.workers.dev/mcp" }
  }
}
```

## --with-auth=workos

When the server is multi-tenant (different users see different tools or different data), wire WorkOS first:

```
Skill ro:workos
```

Then in `src/index.ts`, gate the `MyMCP.serve` call behind a WorkOS-issued bearer:

```ts
import { getAuth } from './lib/auth';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const auth = getAuth(env);
    const result = await auth.withAuth(request);
    if (!result.auth.user) return new Response('Unauthorized', { status: 401 });

    // pass user context into the agent state
    const agent = MyMCP.serve('/mcp', { binding: 'MyMCP' });
    return agent.fetch(request, env, ctx);
  },
};
```

In tools, read `this.props` (set by McpAgent from request context) to scope queries to the current user. WorkOS organisations let you scope further (per-org tools, per-org data).

For a public anonymous MCP server, skip auth. Most public MCP servers should be anonymous + rate-limited rather than authenticated.

## --with-card

The MCP Server Card spec (SEP-2127, working group chartered 2026-03-26) defines a `/.well-known/mcp/server-card.json` document that clients can fetch to discover the server's identity, capabilities, and auth requirements without connecting first.

**Status as of 2026-04-30: Draft.** The PR is open in the modelcontextprotocol/spec repo, not merged. The shape is mostly stable but the final field set may shift before merge, especially `tools` and `auth`.

This skill ships the route as **opt-in**. Default scaffold structures the server's metadata so adding the route later is a 30-minute job, but does not serve the route by default.

When `--with-card` is passed:

```ts
// src/well-known.ts
export function serverCard(env: Env) {
  return {
    schema: 'https://modelcontextprotocol.io/schemas/server-card-draft.json',
    name: 'my-server',
    version: '0.1.0',
    description: 'What this server does in one sentence.',
    transport: { type: 'streamable-http', url: 'https://my-server.workers.dev/mcp' },
    auth: env.AUTH_REQUIRED === 'true' ? { type: 'oauth2', authorization_url: env.WORKOS_AUTH_URL } : { type: 'none' },
    capabilities: {
      tools: true,
      resources: false,
      prompts: false,
    },
    contact: { url: 'https://github.com/<you>/<repo>' },
  };
}
```

```ts
// src/index.ts (additions)
import { serverCard } from './well-known';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const url = new URL(request.url);
    if (url.pathname === '/.well-known/mcp/server-card.json') {
      return Response.json(serverCard(env), {
        headers: { 'cache-control': 'public, max-age=300' },
      });
    }
    return MyMCP.serve('/mcp', { binding: 'MyMCP' }).fetch(request, env, ctx);
  },
};
```

Re-check the schema URL and field set when the spec lands. Comparison context: `llm-wiki-ai-research/wiki/concepts/mcp-server-cards.md`.

## Resources and prompts

Same registration shape as tools.

```ts
server.registerResource(
  'docs',
  'docs://readme',
  { title: 'Project README', mimeType: 'text/markdown' },
  async () => ({
    contents: [{ uri: 'docs://readme', mimeType: 'text/markdown', text: '# Hello\n' }],
  }),
);

server.registerPrompt(
  'review',
  {
    title: 'Code review prompt',
    description: 'Generate a structured review for a diff',
    argsSchema: z.object({ diff: z.string() }),
  },
  async ({ diff }) => ({
    messages: [{ role: 'user', content: { type: 'text', text: `Review this diff:\n\n${diff}` } }],
  }),
);
```

## Publishing

### Stdio

```bash
pnpm build
pnpm publish --access public
```

Consumers install via `npx`:

```bash
claude mcp add my-mcp-server -- npx -y my-mcp-server
```

Or via package manager + manual `mcp.json` entry pointing at the installed binary.

### Hosted

```bash
wrangler deploy
```

Consumers add the URL to `mcp.json`. No npm publish step.

For discoverability, register in community MCP catalogs (e.g. mcp.so, smithery.ai). The opt-in server-card route helps once the spec lands; until then, a clean README is the discoverability surface.

## Observability

- **Hosted**: Workers Observability is on by the `wrangler.toml` snippet above. Query via the Cloudflare dashboard or the `cloudflare-observability` MCP (`/ro:cloudflare-mcp-setup` wires it).
- **Stdio**: log to stderr (stdout is reserved for the MCP protocol stream). `console.error()` is fine; for structured logs use `pino` writing to `process.stderr`.

```ts
console.error(JSON.stringify({ level: 'info', tool: 'fetch_user', userId: id, ms: Date.now() - start }));
```

Never write to stdout from a stdio server outside the MCP transport. Stray stdout breaks the JSON-RPC framing and clients disconnect.

## Safety

- For `--hosted`, set rate limits in `wrangler.toml` (`[[unsafe.bindings]]` Rate Limiting binding) before going public. A public anonymous MCP with no rate limit is a bill-amplifier.
- For `--with-auth=workos`, gate the auth check at the Worker entry, not inside individual tools. A tool that forgets to check `this.props.user` is an authorisation bug waiting to happen.
- Stdio servers run with the privileges of whoever invoked them. Treat `fs` and `child_process` access as a security boundary; document any tool that reads files or runs commands.
- The MCP Inspector (`pnpm dev`) is local-only. Do not point a deployed Inspector at a hosted server; the protocol is unauthenticated by default and the Inspector is for development.

## See also

- `cloudflare:build-mcp` for the upstream Cloudflare McpAgent scaffold (composes with this skill)
- `/ro:workos` when wiring `--with-auth=workos`
- `/ro:cf-ship` to deploy the hosted variant the canonical way
- `/ro:cloudflare-mcp-setup` to wire the `cloudflare-observability` MCP for log queries
- MCP TypeScript SDK: `https://github.com/modelcontextprotocol/typescript-sdk`, context7 ID `/modelcontextprotocol/typescript-sdk`
- Server-card research: `llm-wiki-ai-research/wiki/concepts/mcp-server-cards.md`
