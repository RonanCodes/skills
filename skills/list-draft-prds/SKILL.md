---
name: list-draft-prds
description: List open GitHub issues labelled `prd:draft` in the current repo — the agent-native repo's "ideas inbox". Draft PRDs are NEVER auto-picked-up by Ralph, planner-worker, agentic-e2e-flow, or night-shift; they sit waiting to be grilled into real PRDs (Pocock 7-section template) before the label is swapped to the repo's gate label (`ready-for-agent` by default, `Sandcastle` / `swarm` per project). Use when you want to see what ideas are sitting, triage your drafts, or pick one to grill. Triggers on "what draft PRDs do I have", "show me my drafts", "list ideas", "what ideas are sitting", "any draft PRDs", "list draft prds", "/ro:list-draft-prds".
category: workflow
argument-hint: [--label <draft-label>] [--limit <N>]
allowed-tools: Bash AskUserQuestion
---

# List Draft PRDs

The "ideas inbox" view for an agent-native repo. Lists open issues labelled `prd:draft` so the user can decide which one to grill into a real Pocock-shaped PRD.

## Why this exists

In the agent-native repo pattern (see `agent-native-repo-pocock`), GitHub issues ARE the backlog. Two label states gate the queue:

| Label | Meaning | Picked up by autonomous runs? |
|---|---|---|
| `prd:draft` | Captured idea, NOT yet shaped as a real PRD. Body is freeform notes, not the Pocock 7-section template. | **NO.** Never. |
| `ready-for-agent` (or project synonym like `Sandcastle`, `swarm`) | Grilled and shaped. Parent PRDs (body opens `## Problem Statement`) or slice issues (body opens `## Parent\n\n#<N>`). | **YES** — Ralph, planner-worker, agentic-e2e-flow, night-shift all consume from here. |

Draft PRDs are the user's idea capture. They wait until the user runs `/grill` on them (which uses `grill-with-docs` under the hood), at which point the body is rewritten into the 7-section Pocock template and the label is swapped from `prd:draft` to the gate label.

This skill is the "what's sitting in my drafts" view. It does NOT promote anything itself — promotion is the user's call, driven by `/grill`.

## Pre-flight

1. **Detect gh remote.** Run `gh repo view --json nameWithOwner -q .nameWithOwner` — if that errors, exit cleanly with:

   > "Not in a gh-remote repo. `/ro:list-draft-prds` only works inside a repo with a GitHub remote. The `prd:draft` convention lives on GitHub issues."

2. **Resolve the draft label.** Default `prd:draft`. Override via `--label <name>` (rare; the convention is to use `prd:draft` across all agent-native repos).

## Step 1: Query open drafts

```bash
gh issue list \
  --label prd:draft \
  --state open \
  --json number,title,updatedAt,body,labels,url \
  --limit "${LIMIT:-30}"
```

Parse the JSON. Sort by `updatedAt` descending (most recently touched first).

## Step 2: Print the list

For each draft, render:

```
#<num>  <title>  · updated <relative-time>
        <first ~2 non-blank lines of body, truncated to ~140 chars total>
        labels: prd:draft, <any-others>
        <url>
```

Use a numbered list (1., 2., 3., ...) so the user can refer to "the first one" / "number 2" in conversation.

Relative-time should be human-friendly:
- `< 1h`: "just now" / "23 min ago"
- `< 24h`: "5h ago"
- `< 7d`: "3d ago"
- else: ISO date `2026-05-12`

If `0` drafts found, print:

```
No draft PRDs in this repo.

Capture an idea by writing a fresh GH issue with the `prd:draft` label —
or run `/ro:write-a-prd --draft` (TBD) when that ships. To turn a draft
into a real PRD, run `/grill` on the issue and the body gets rewritten
into Matt Pocock's 7-section template + the label swaps to your repo's
gate label (`ready-for-agent` by default).
```

Then exit. No question asked.

## Step 3: Offer to grill one

After listing (and only if N >= 1), ask via `AskUserQuestion`:

> "Which draft do you want to grill into a real PRD?"

Options:

- Each draft as its own option: `"#<num> — <title>"` (cap at first ~60 chars of title)
- Final option: `"none, just listing"` (the escape hatch)

On user pick:

- If "none" → exit cleanly. Print "OK, drafts left as-is."
- If a draft is picked → print "Next step: `/grill <issue-number>` to shape `#<num>` into a real PRD." and exit. **Do NOT invoke `/grill` directly from this skill** — the user controls when grilling starts; this skill is read-only over the issue backlog.

The "do not invoke" rule is load-bearing: this skill is the inbox view, not the action. Bundling grill-dispatch here would couple the inbox to a single grill flow and surprise users who wanted to triage manually.

## Usage

```
/ro:list-draft-prds                        # Default: list up to 30 open prd:draft issues
/ro:list-draft-prds --limit 10             # Smaller list
/ro:list-draft-prds --label my-drafts      # Custom draft label (rare)
```

## Tip — pair with agentic-e2e-flow

`/agentic-e2e-flow` checks for open `prd:draft` issues in its pre-flight and offers to grill one before writing a fresh PRD. If you're not sure whether to start from a draft or from scratch, run `/ro:list-draft-prds` first to see the inbox.

## Errors

| Condition | Message |
|---|---|
| No gh remote | "Not in a gh-remote repo. `/ro:list-draft-prds` only works inside a repo with a GitHub remote." |
| `gh` not authed | "`gh` is not authenticated. Run `gh auth login` first." |
| Label missing (gh returns 0 issues but label doesn't exist) | Distinguish from "0 drafts" by checking `gh label list --json name -q '.[].name'` first. If label missing, suggest creating it: `gh label create prd:draft --color CCCCCC --description "Captured idea, not yet a real PRD"`. |

## Provenance

Created 2026-05-14 alongside the `prd:draft` convention. The convention itself is:

- Idea capture → GH issue with `prd:draft` label (freeform body, NOT the Pocock template)
- Drafts NEVER auto-picked-up by autonomous runs (Ralph, planner-worker, agentic-e2e-flow, night-shift)
- Promotion via `/grill` → rewrites body into 7-section template, swaps label `prd:draft` → `ready-for-agent` (or project synonym configured in `docs/agents/triage-labels.md`)

See also `agent-native-repo-pocock` pattern page in `llm-wiki-skill-lab`.

## See also

- `/grill` — the dispatcher that routes to `grill-with-docs` to promote a draft into a real PRD
- `/ro:write-a-prd` — write a fresh PRD from scratch (skipping the draft stage)
- `/agentic-e2e-flow` — full end-to-end pipeline; offers to grill a draft as its first gate
- `/ro:ralph`, `/ro:planner-worker`, `/ro:night-shift` — autonomous runs that exclude `prd:draft` from their queues
