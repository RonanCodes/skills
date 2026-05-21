---
name: jira
description: Create, read, update, comment on, and transition Jira tickets via the Atlassian Remote MCP server. Defaults to the DAFO (Dataforce) project on the Simplicity Labs site. Use when user wants to file a Jira ticket, move a DAFO ticket between board columns, list the board, assign work, or comment on a ticket. Pairs with /ro:confluence and /ro:jira-to-gh.
category: project-management
argument-hint: [create <Bug|Story|Task|Feature> "title" [--body "..."] [--assignee <accountId>] [--label <l>] | move <KEY> <status> | list [--status <s>] | show <KEY> | comment <KEY> "body" | assign <KEY> <accountId|me|unassign>] [--project <key>] [--site <host>]
allowed-tools: Bash(claude mcp *) Bash(grep *) Read
---

# Jira

Opinionated wrapper around the Atlassian Remote MCP server's Jira tools. Reads defaults from `~/.claude/.env` so the common case (DAFO ticket on `simplicitylabs.atlassian.net`) is one short line.

## Usage

```
/ro:jira create Bug "Reorder watch fails when SKU has spaces" --body "Repro: ..."
/ro:jira create Story "As a Taskforce ops user, I want bulk inventory adjust"
/ro:jira create Task  "Refresh Nango proxy header docs"
/ro:jira move DAFO-42 "In Progress"
/ro:jira move DAFO-42 done
/ro:jira list                                  # active sprint, all statuses
/ro:jira list --status "In Review"
/ro:jira show DAFO-42
/ro:jira comment DAFO-42 "Blocked on Taskforce confirming the SKU format"
/ro:jira assign DAFO-42 me
```

Override defaults per-call: `--project ANOTHER --site other.atlassian.net`.

## Prerequisites

1. **Atlassian Remote MCP installed** (one-time, user scope):
   ```bash
   claude mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2
   ```
2. **OAuth completed** — run `/mcp` in any Claude Code session and step through the browser auth for the `atlassian` server. The token persists across sessions.
3. **Defaults in `~/.claude/.env`** (already wired for Ronan):
   ```
   ATLASSIAN_SITE=simplicitylabs.atlassian.net
   ATLASSIAN_JIRA_PROJECT_DEFAULT=DAFO
   ATLASSIAN_JIRA_BOARD_DEFAULT=34
   ```

If `claude mcp list` does not show `atlassian` as connected, this skill cannot run. Tell the user to install + OAuth before proceeding.

## How to run each verb

The skill is a playbook over the Atlassian MCP tools — at runtime, look up the actual tool names via the live `mcp__atlassian__*` tool list (Atlassian iterates on these). Map verbs to tools using the table below.

| Verb | What to do | Atlassian MCP tool to call (typical name) |
|---|---|---|
| `create` | Read defaults from `~/.claude/.env`, build payload (project key, issue type, summary, optional description, labels, assignee), call create | `createJiraIssue` / `atlassian_jira_create_issue` |
| `move` | Look up valid transitions for the ticket, fuzzy-match the user's status string, apply | `transitionJiraIssue` / `atlassian_jira_transition_issue` |
| `list` | Build JQL: `project = ${PROJECT} AND sprint in openSprints()`, optional `AND status = "${status}"`, render compact table (key, type, status, assignee, title) | `searchJiraIssuesUsingJql` |
| `show` | Fetch full issue, render summary + description + status + assignee + last 3 comments + linked Confluence pages | `getJiraIssue` |
| `comment` | Post comment body, return URL to ticket | `addJiraIssueComment` |
| `assign` | Resolve `me` to the OAuthed user's accountId; pass `unassign` as null | `assignJiraIssue` or update via `editJiraIssue` |

### DAFO board statuses (as defined by Ronan in the partnership chat)

| Column | When to use |
|---|---|
| **To Do** | Ticket exists, not picked up yet |
| **In Progress** | Active work (Skip or Ronan) |
| **In Review** | PR open, waiting on review/agreement; partner-facing Tasks may sit here longer |
| **Done** | Live in production — ticket moves to Done only when shipped |

Be strict on the Done rule when the user asks to close a ticket: only move to Done if the work is deployed. Otherwise use In Review.

### Issue types (DAFO convention)

- **Bug** — defect in shipped behaviour
- **Story** — user-facing feature (write from user's perspective)
- **Task** — non-user work (admin, ops, infra, partner agreement)
- **Feature** — epic-like umbrella over multiple Stories (used sparingly)

Default issue type when ambiguous: ask the user. Do not silently pick.

## What to return after each action

- `create`: the new ticket key + browser URL (e.g. `https://simplicitylabs.atlassian.net/browse/DAFO-42`)
- `move`: confirm old status → new status + ticket URL
- `list`: a markdown table (no more than 30 rows; if more, paginate by sprint)
- `show`: structured summary above, raw description below
- `comment`/`assign`: confirm + URL

Always print the URL so the user can click through in Obsidian / terminal.

## Bridges

- **Jira ↔ GitHub**: see `/ro:jira-to-gh` to mirror a DAFO ticket as a GH issue in `RonanCodes/dataforce` or to seed `/ro:write-a-prd` from the ticket body.
- **Jira ↔ Confluence**: see `/ro:confluence link <page-id> DAFO-42` to attach research docs to a ticket.
- **Jira ↔ wiki**: research conducted in a `/ro:jira show` walk-through can be ingested into `llm-wiki-simplicity-taskforce-partnership` via `/ingest text` with the ticket URL as source.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| "No atlassian MCP tools available" | OAuth not done | `/mcp` then complete browser flow |
| "Invalid transition" on `move` | Status name doesn't match the workflow exactly | Skill should fuzzy-match; if it can't, list valid transitions and ask |
| "Project not found" | DAFO default not loaded or site wrong | Verify `~/.claude/.env` has `ATLASSIAN_*` defaults; pass `--project` / `--site` explicitly |
| Tickets created with wrong reporter | OAuthed account is not the intended one | Re-run `/mcp` and re-auth as the correct user |

## Related

- `[[atlassian-rovo-mcp]]` in `llm-wiki-skill-lab` (pattern note — write on first real use)
- DAFO board: https://simplicitylabs.atlassian.net/jira/software/projects/DAFO/boards/34
- Confluence space: https://simplicitylabs.atlassian.net/wiki/spaces/dataforce/overview
