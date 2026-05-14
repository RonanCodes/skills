---
name: new-app
description: Generic "start a new project" orchestrator. Walks the canonical [[stack-decision-map]] tree (audience → app shape → scale → reactivity → EU residency → owns-the-table → connectors → payments) using AskUserQuestion, lands on a leaf, dispatches to the framework-specific skill that builds it (`/ro:new-tanstack-app`, `/ro:new-astro-app`, `/ro:new-mcp-server`, ...). Use when the user wants to start, create, scaffold, bootstrap, or begin a new project but isn't sure which stack fits — or when you'd rather walk the decision tree once than memorise four sibling skills. Routes to the right downstream skill so users never need to know the catalogue.
category: project-setup
argument-hint: [<app-name>] [--from-doc] [--explain]
allowed-tools: Bash(cat *) Bash(git *) Read AskUserQuestion
---

# New App (decision-tree dispatcher)

A thin orchestrator that walks `[[stack-decision-map]]` and hands off to the framework-specific skill once the user lands on a leaf. **Doesn't scaffold anything itself** — every actual file write happens in the dispatched-to skill.

If you already know which framework you want, skip this and call the leaf skill directly:
- `/ro:new-tanstack-app` — server-leaning SaaS / app
- `/ro:new-astro-app` — static-leaning marketing / portfolio / blog
- `/ro:new-mcp-server` — MCP server (McpAgent on Workers, optional `--with-card`)

This skill is the "I'm not sure" entry point.

**Every dispatch path scaffolds a `/styleguide` route by default** (role-gated to `superadmin + staff` when auth is wired, dev-only otherwise). Downstream skills like `/ro:new-tanstack-app` and `/ro:new-astro-app` invoke `/ro:design-system-create --showcase` as part of their flow; this orchestrator doesn't need to ask about it.

## Usage

```
/ro:new-app                         # walk every question
/ro:new-app my-site                 # pre-fill the app name
/ro:new-app --from-doc              # re-read stack-decision-map.md before walking (don't trust cached snapshot)
/ro:new-app --explain               # at each fork, print the rationale from the canon table
```

## Canonical source

The decision tree this skill walks lives in `[[stack-decision-map]]` (LLM wiki research vault). Treat that doc as the source of truth — the prompts below reflect a 2026-05-05 snapshot. If the wiki tree changes (new framework leaf, removed alt, etc.), update the dispatch matrix at the bottom of this file rather than re-deriving the questions from scratch.

If `--from-doc` is passed and the wiki repo is checked out at `~/Dev/ai-projects/llm-wiki/vaults/llm-wiki-research`, read the source mermaid block before asking anything — that's the authoritative version.

## Process

### 1. Walk the decision tree

Use `AskUserQuestion` for each fork. Keep the wording faithful to the wiki tree:

**Q1 — Audience (`Q_AUDIENCE`):**
- Power user with skill kit *(default; this skill exists for you)*
- First-app vibe coder *(escape-hatch — recommend the Alex Finn stack, see [[stack-canon-vs-alex-finn]], skip the rest of the tree)*

**Q2 — App shape (`Q_SHAPE`):**
- Web SaaS *(server-leaning, has dynamic data, auth, etc.)*
- Marketing / landing / portfolio / blog *(static-leaning, content-heavy)*
- MCP server *(LLM tool/resource provider)*
- 2D game
- 3D experience
- Mobile-first PWA

If **Marketing/static**, ask **Q3a — Existing site?**
- No, fresh build → dispatch `/ro:new-astro-app <app-name>`
- Yes, existing live site → dispatch `/ro:migrate-to-astro`

If **Web SaaS**, walk Q_SCALE → Q_REACTIVE → Q_EU → Q_OWNTABLE → Q_CONNECTORS → Q_PAYMENTS — but **don't re-implement those questions here**. Just dispatch `/ro:new-tanstack-app <app-name>` and let it walk its own `--interactive` flow with the same questions. (Different sub-skill, same questions, single source of truth.)

If **MCP server**: dispatch `/ro:new-mcp-server <app-name>`.

If **2D game** | **3D experience**: those leaves point to `tbd:phaser-game` / `tbd:r3f` etc. — print the leaf name and a short note that the dedicated skill is pending.

If **Mobile-first PWA**: dispatch `/ro:new-tanstack-app <app-name> --pwa` (which then composes `/ro:pwa-install` post-bootstrap).

### 2. Confirm the dispatch

Before invoking the chosen skill, summarise the decisions in one paragraph and print the exact downstream invocation. The user can interrupt if anything looks wrong.

```
Based on your answers:
  - audience: power-user
  - shape: marketing site
  - migrate: no, fresh build

About to run: /ro:new-astro-app <app-name>

Continue? (yes/edit-decisions/no)
```

### 3. Hand off

Invoke the dispatched skill. From here on, this skill is silent — the leaf skill drives.

## Dispatch matrix (current as of 2026-05-05)

| User picks | Then... | Dispatches to |
|---|---|---|
| Audience: vibe-coder | (no further questions) | (recommend Alex Finn stack, no skill dispatch) |
| Shape: Web SaaS | Walk SaaS-specific tree inside the skill | `/ro:new-tanstack-app <app-name> --interactive` |
| Shape: Marketing → fresh | (none) | `/ro:new-astro-app <app-name>` |
| Shape: Marketing → migrate | (none — migrate-app handles the source-side qs) | `/ro:migrate-to-astro` |
| Shape: MCP server | (sub-skill picks transport) | `/ro:new-mcp-server <app-name>` |
| Shape: Mobile PWA | (sub-skill composes PWA install) | `/ro:new-tanstack-app <app-name> --pwa` |
| Shape: 2D game | (no skill yet) | placeholder: `tbd:phaser-game` |
| Shape: 3D experience | (no skill yet) | placeholder: `tbd:r3f` / `tbd:babylon` |

When the wiki gains a new framework leaf, add a row above and a question/answer pair in step 1.

## See also

- `[[stack-decision-map]]` — the canonical tree this skill walks
- `/ro:migrate-app` — the migration-side sibling (same dispatcher pattern, different leaf set)
- `/ro:new-tanstack-app`, `/ro:new-astro-app`, `/ro:new-mcp-server` — the leaf skills this dispatcher routes to
