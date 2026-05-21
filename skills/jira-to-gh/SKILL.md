---
name: jira-to-gh
description: Bridge a Jira (DAFO) ticket to the agent-native GitHub repo flow. Two modes — --mirror creates a one-to-one GH issue in RonanCodes/dataforce with linkbacks both ways; --prd seeds /ro:write-a-prd from the ticket body and publishes the PRD as a GH parent issue. Use when a Taskforce-filed DAFO ticket needs to enter the Skip+Ronan implementation pipeline.
category: project-management
argument-hint: <DAFO-KEY> [--mirror | --prd] [--repo <owner/name>] [--label <l>]
allowed-tools: Bash(gh *) Bash(claude mcp *) Bash(grep *) Read
---

# Jira → GitHub bridge

The Taskforce partners file work in Jira (DAFO board). Skip and Ronan implement in `RonanCodes/dataforce` using the agent-native repo pattern (ready-for-agent label, PRDs as GH issues, ralph/planner-worker consume from the queue). This skill is the bridge.

One-way by default: Jira → GitHub. Status drift is acceptable — Jira reflects the partner-facing state ("In Review" until they sign off), GH reflects the implementation state ("merged" the moment a PR lands). Skill ensures URLs are linked both ways so anyone can navigate.

## Usage

```
/ro:jira-to-gh DAFO-42                    # default: --mirror, into RonanCodes/dataforce
/ro:jira-to-gh DAFO-42 --mirror           # one-to-one GH issue
/ro:jira-to-gh DAFO-42 --prd              # seed /ro:write-a-prd from ticket body, publish as GH parent
/ro:jira-to-gh DAFO-42 --mirror --repo RonanCodes/some-other-repo
```

## Prerequisites

- `/ro:jira` working (atlassian MCP authenticated)
- `gh` CLI authenticated against `RonanCodes` (or whichever target org)
- For `--prd`: the `/ro:write-a-prd` skill installed; `/ro:repo-mode` resolved to `personal` for the target repo so the PRD publishes to GH and not `.ralph/`

## Mode: `--mirror` (default)

For: small / well-specified DAFO tickets that map to a single agent slice.

Steps:

1. **Fetch the Jira ticket** via the atlassian MCP (typically `getJiraIssue`). Capture: summary, description, type (Bug/Story/Task/Feature), labels, reporter, current status.
2. **Build the GH issue body** in this shape:
   ```markdown
   ## Source
   Mirrored from Jira **DAFO-42** — https://simplicitylabs.atlassian.net/browse/DAFO-42

   Reporter: <Jira reporter name>
   Type: <Bug|Story|Task|Feature>

   ## Description
   <Jira description, converted to GitHub-flavoured markdown>
   ```
3. **Create the GH issue** via `gh issue create`:
   - Title: same as Jira summary
   - Labels: `ready-for-agent`, plus a type-derived label (`bug`, `feature`, `task`)
   - Body: as above
4. **Comment on the Jira ticket** via the atlassian MCP with the GH issue URL:
   ```
   Mirrored to GitHub for implementation: <gh issue URL>
   Status updates will appear here when the GH issue closes.
   ```
5. **Print both URLs** + the issue number so the user can navigate.

## Mode: `--prd`

For: larger DAFO tickets that need decomposition into vertical slices, or anything the user wants grilled with Matt Pocock's 7-section template.

Steps:

1. **Fetch the Jira ticket** as in `--mirror`.
2. **Hand off to `/ro:write-a-prd`** with the ticket body as the seed brief. The PRD interview will grill on Problem / Users / Scope / Out-of-Scope / Acceptance / Risks / Sequencing.
3. Once the PRD is published as a GH issue (write-a-prd handles that in personal repo mode), **comment on the Jira ticket**:
   ```
   PRD authored from this ticket: <gh parent issue URL>
   Next: slicing into vertical-slice issues via /ro:slice-into-issues.
   ```
4. **Recommend the next step** — `/ro:slice-into-issues <PRD#>` — but do not run it automatically. User decides when to slice.
5. **Print both URLs** + suggest the user invoke `/ro:slice-into-issues` when ready.

## Status sync — keep it simple

This skill does NOT auto-sync status. Reason: Jira lifecycle (Taskforce-facing) and GH lifecycle (implementation-facing) diverge intentionally. A DAFO ticket can sit in "In Review" while three GH PRs ship and re-ship around it.

Convention:

- When the GH issue closes (PR merged with `Closes #N`), the user (or a close-with-summary subagent) should run `/ro:jira move DAFO-42 "In Review"` and post a comment with the deploy URL.
- When the change is actually live in production and Taskforce can verify, `/ro:jira move DAFO-42 done`.

The "Done means shipped" rule from the partnership chat is preserved by keeping the moves manual.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `gh: command not found` or auth error | gh not installed / not auth'd | Install gh, run `gh auth login` |
| Jira ticket fetched but description is empty | DAFO ticket was filed without body | Fetch comments too and use the first comment as description |
| Markdown formatting from Jira renders ugly on GH | Atlassian wiki markup vs GitHub MD difference | The MCP usually returns ADF/markdown; if it returns wiki markup, run through a converter or strip noise manually |
| `/ro:write-a-prd` opens but doesn't know about the Jira context | Seed not passed cleanly | Pre-format the brief as a single paragraph before the handoff; mention the DAFO key in the first line |

## Why one-way (not bidirectional)

- Two-way sync invites loop bugs (close-on-close ping-pong) and conflict cases (status drift while edits are in flight).
- The partner contract is "Jira is the source of truth for partner-facing state, GH is the source of truth for implementation state, links bridge them." That contract is preserved by manual status moves on the Jira side.
- If bidirectional becomes painful enough to want, file as a DAFO ticket and revisit. Don't pre-build for it.

## Related

- `/ro:jira` — basic ticket CRUD
- `/ro:write-a-prd` — Matt Pocock 7-section PRD interview, publishes to GH
- `/ro:slice-into-issues` — vertical-slice a PRD into ready-for-agent children
- `/ro:ralph`, `/ro:planner-worker` — consume the ready-for-agent queue
- Partnership pattern note: `[[agent-native-repo-pocock]]` in `llm-wiki-skill-lab`
