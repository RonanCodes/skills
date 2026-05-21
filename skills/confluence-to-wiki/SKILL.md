---
name: confluence-to-wiki
description: Pull a Confluence page into an llm-wiki vault as a source-note via the wiki's /ingest convention. One-way (Confluence → wiki), defaults to llm-wiki-simplicity-taskforce-partnership. Use when partner-shared research in Confluence needs to live in the wiki for query, synthesis, or cross-vault linking. Pairs with /ro:confluence and /ingest.
category: knowledge-capture
argument-hint: <page-id-or-url> [--vault <vault-name>] [--with-children] [--site <host>]
allowed-tools: Bash(claude mcp *) Bash(grep *) Read Write
---

# Confluence → Wiki

Mirrors a Confluence page (or page tree) into an `llm-wiki-*` vault as a source-note. Conforms to the wiki's `/ingest` source-note conventions: frontmatter, inline `## Sources` section, and the canonical wiki page-type fields.

One-way: changes in Confluence are reflected by re-running this skill; changes in the wiki do not flow back. The Confluence page remains the source of truth for partner-shared content.

## Usage

```
/ro:confluence-to-wiki 123456789
/ro:confluence-to-wiki https://simplicitylabs.atlassian.net/wiki/spaces/dataforce/pages/123456789/Inventory+sync+algorithm+v2
/ro:confluence-to-wiki 123456789 --vault llm-wiki-simplicity-taskforce-partnership
/ro:confluence-to-wiki 123456789 --with-children   # pull the page and all descendants
```

Default vault: `llm-wiki-simplicity-taskforce-partnership` (matches the dataforce Confluence space).

## Prerequisites

- atlassian MCP installed + OAuthed (see `/ro:confluence` for setup)
- Target vault exists under `~/Dev/ai-projects/llm-wiki/vaults/<vault-name>/`. If not, run `/vault-create` first.

## Steps

1. **Resolve the page id** — accept either a numeric id or a Confluence URL (extract the id from the path).
2. **Fetch the page** via the atlassian MCP (typically `getConfluencePage`). Get title, body, last-updated, author, space, parent.
3. **Build the wiki source-note** — write to `vaults/<vault>/wiki/sources/confluence-<page-id>-<slug>.md`:
   ```markdown
   ---
   title: <Confluence page title>
   page-type: source-note
   source-type: confluence
   source-url: <full Confluence URL>
   source-id: <page-id>
   source-space: <space-key>
   author: <Confluence author display name>
   created: <ISO date>
   updated: <ISO date — Confluence last-modified>
   mirrored: <today's ISO date>
   domain: <vault default domain>
   tags: [confluence, partnership]
   sources:
     - <full Confluence URL>
   related: []
   ---

   # <Confluence page title>

   > Mirrored from Confluence on <date>. Source of truth: <URL>

   <converted body as markdown>

   ## Sources

   - [<page title>](<full Confluence URL>) — Confluence page, space `<space-key>`, last updated <date>
   ```
4. **Update the vault log** — append a one-line entry to `vaults/<vault>/log.md`:
   ```
   - <date>: mirrored Confluence page "<title>" (<id>) → wiki/sources/confluence-<id>-<slug>.md
   ```
5. **If `--with-children`**: recurse, mirroring each descendant. Link parent ↔ children in the `related:` frontmatter array.
6. **Print** the wiki page path and an `obsidian://open` URL so the user can jump straight in.

## Body conversion

The Atlassian MCP typically returns Confluence content as ADF (Atlassian Document Format) or markdown. Convert to clean wiki markdown:

- Headings, lists, code blocks, tables: straight conversion
- Inline `<ac:image>` macros → `![alt](image-url)` (download the image to `vaults/<vault>/wiki/assets/` and rewrite the URL to relative)
- Smart Links to Jira tickets → leave the URL inline; the wiki doesn't need to render the panel
- Embedded Confluence pages → leave as a link with `> Embedded Confluence: <url>` blockquote
- User mentions → `@<display name>` (lookup their actual entity page in the vault is out-of-scope for v1)

If conversion is lossy enough that the page reads badly, fall back to including the raw ADF JSON as a code block at the bottom of the source-note and flag in the body: `> Raw ADF preserved below — markdown conversion was partial.`

## When to use vs `/ingest`

- **`/ro:confluence-to-wiki`** — for pages already in Confluence. Wiki-side becomes a mirror. Re-run to refresh.
- **`/ingest <url>`** with a Confluence URL — should route here automatically once the `confluence:` source-type handler is added to the wiki's `/ingest` router. Until then, this skill is the explicit path.
- **`/ro:confluence create`** — when authoring NEW content that needs to live in Confluence (partner-facing). After publishing, optionally mirror back to the wiki via this skill if it's worth querying.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No atlassian MCP tools" | OAuth not done | `/mcp` → browser auth |
| "Vault not found" | Target vault doesn't exist | Run `/vault-create <name>` first |
| Body conversion mangles tables | ADF table → markdown is lossy for complex tables | Include raw ADF block as fallback (see above) |
| Page has restricted access | OAuthed user doesn't have view permission on the page | Have the page owner share it, or use an account with broader access |

## Related

- `/ro:confluence` — page CRUD inside Confluence
- `/ingest` — wiki's generic ingestion router (will get a `confluence:` handler hooked in separately)
- `/promote` — graduate a Confluence-sourced page from this Spoke vault into `llm-wiki-research` (Hub) if it's reusable knowledge
- `llm-wiki-simplicity-taskforce-partnership` — default target vault
