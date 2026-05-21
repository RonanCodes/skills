---
name: confluence
description: Create, update, read, and Smart-Link Confluence pages via the Atlassian Remote MCP server. Defaults to the dataforce space on the Simplicity Labs site. Use when user wants to draft a research doc, post meeting notes, or link a Confluence page to a Jira ticket. Pairs with /ro:jira and /ro:confluence-to-wiki.
category: project-management
argument-hint: [create "title" [--parent <page-id>] [--body-file <path>] | update <page-id> [--body-file <path>] | show <page-id> | link <page-id> <JIRA-KEY> | list [--parent <page-id>]] [--space <key>] [--site <host>]
allowed-tools: Bash(claude mcp *) Bash(grep *) Read Write
---

# Confluence

Opinionated wrapper around the Atlassian Remote MCP server's Confluence tools. Reads defaults from `~/.claude/.env`. Common case is the `dataforce` space on `simplicitylabs.atlassian.net`.

## Usage

```
/ro:confluence create "Inventory sync algorithm v2" --body-file ./notes.md
/ro:confluence create "Taskforce x Simplicity weekly — 2026-05-22" --parent <weekly-notes-page-id>
/ro:confluence update <page-id> --body-file ./revised.md
/ro:confluence show <page-id>
/ro:confluence link <page-id> DAFO-42         # Smart Link: append the Jira issue panel
/ro:confluence list --parent <page-id>        # children under a parent
```

Override defaults: `--space <key> --site <host>`.

## Prerequisites

Same as `/ro:jira`:
1. `claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2`
2. `/mcp` → OAuth the `atlassian` server in browser
3. Defaults in `~/.claude/.env`:
   ```
   ATLASSIAN_SITE=simplicitylabs.atlassian.net
   ATLASSIAN_CONFLUENCE_SPACE_DEFAULT=dataforce
   ```

## How to run each verb

Use the live `mcp__atlassian__*` tools at runtime. Typical mapping:

| Verb | What to do | Atlassian MCP tool (typical name) |
|---|---|---|
| `create` | Convert body to Atlassian storage format (the MCP usually accepts markdown and converts), set space + optional parent, post | `createConfluencePage` |
| `update` | Fetch current version, increment, post new body | `updateConfluencePage` |
| `show` | Fetch page, render title + URL + body as markdown | `getConfluencePage` |
| `link` | Append an `inline-card` / Smart Link macro for the Jira issue URL to the page body, then update. Alternatively, comment on the Jira ticket with the Confluence URL — do both for two-way visibility | `updateConfluencePage` + `addJiraIssueComment` |
| `list` | List children of a parent page | `getConfluenceChildren` / `searchConfluenceUsingCql` |

### Body input

- Prefer `--body-file <path>` over inline `--body`. Confluence pages are long; quoting markdown on the command line is painful.
- Markdown is the input format; the MCP handles conversion to storage format. If the conversion mangles tables/code blocks, fall back to writing storage-format XHTML directly and pass `--raw`.

### Smart Linking to Jira

When linking a Confluence page to a DAFO ticket:

1. Append a short context line to the Confluence page body: `> Related Jira: <ticket URL>`
2. The Atlassian renderer turns that into a Jira issue panel automatically (Smart Links). No special macro needed in most cases.
3. Mirror back: comment on the Jira ticket with the Confluence page URL.

This gives partners a clickable trail in both directions.

## What to return after each action

- `create` / `update`: page title + URL + parent path (if any)
- `show`: title + URL above, body as markdown below
- `link`: confirmation that both sides were updated + both URLs
- `list`: markdown table of children (title, id, last updated)

## When to use vs `/ingest`

- **Use `/ro:confluence create`** when authoring partner-facing content the Taskforce people need to see in Confluence (meeting notes, agreements, research summaries, RFCs for partner review).
- **Use `/ingest` into `llm-wiki-simplicity-taskforce-partnership`** when capturing private notes, thinking, or research that doesn't need to round-trip with partners. Then `/promote` selected pages into `llm-wiki-research` if they're reusable knowledge.
- **Use `/ro:confluence-to-wiki`** to pull an existing Confluence page into the wiki as a source-note (one-way mirror, doesn't sync back).

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No atlassian MCP tools" | OAuth not done | `/mcp` then browser auth |
| Body renders broken (tables, code) | Markdown → storage conversion edge case | Pass `--raw` and supply storage-format XHTML directly |
| "Space not found" | Default not loaded or space key wrong | Verify `ATLASSIAN_CONFLUENCE_SPACE_DEFAULT=dataforce` in env; pass `--space` |
| Update fails with version conflict | Page edited elsewhere between fetch and post | Re-fetch, re-apply, retry |

## Related

- DAFO board: https://simplicitylabs.atlassian.net/jira/software/projects/DAFO/boards/34
- Dataforce Confluence space: https://simplicitylabs.atlassian.net/wiki/spaces/dataforce/overview
- `/ro:jira` for ticket ops
- `/ro:confluence-to-wiki` for pulling pages into the llm-wiki vault
