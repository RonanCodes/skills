---
name: close-session
description: End-of-session durability checklist that makes clearing context safe. Runs mechanical checks (uncommitted changes, unpushed commits, open PRs, chat-only decisions, new domain terms, ROADMAP staleness, memory entries) and either resolves each inline or queues it as a GitHub issue, ADR, wiki page, or memory note. The point is to walk away knowing nothing important lives only in this conversation. Triggers on "close session", "close the session", "wrap up the session", "end of session", "I'm done for the day", "clear my context", "session close", "let's wrap up", "finishing up", "shutting down for now".
category: workflow
argument-hint: [--quick] [--reflective] [--vault <name>] [--skip <check>]
allowed-tools: Bash Read Write Edit Glob Grep AskUserQuestion
---

# Close Session

Run before clearing context, switching tasks, or stepping away. The goal: every important thing from this session lives in a durable place by the time you finish — code, GitHub issue, ADR, CONTEXT.md, wiki page, ROADMAP entry, log entry, or memory note. Nothing important left stranded in the chat transcript.

## When to use

User says any of:

- "close session" / "close the session" / "session close"
- "wrap up the session" / "let's wrap up" / "finishing up"
- "end of session" / "I'm done for the day"
- "clear my context" / "shutting down for now"
- Before invoking `/clear` or starting a structurally different task

Do NOT use for:

- Mid-task pauses where context is still hot (just keep working)
- Tiny edits where there's nothing to capture
- Inside an autonomous loop (Ralph / planner-worker handle their own state)

## The checklist (8 checks + 1 partnership sub-check, each skippable)

Run in order. Each check is a separate `AskUserQuestion` so the user can resolve, queue, or skip per item.

### Check 1 — Uncommitted changes

```bash
git status --porcelain
```

If any:

- Show the file list and a short diff summary (`git diff --stat`).
- Offer: commit now (open `/ro:commit`) / stash / discard with confirmation / leave for next session (note in chat why).

### Check 2 — Unpushed commits

```bash
git log @{u}..HEAD --oneline 2>/dev/null
```

If any:

- Show the commit list.
- Offer: push now / leave (note why — pre-merge gate? unsigned? not ready?).

Memory `feedback_commit_and_push.md` says push regularly on ralph/autonomous work; outside those modes, "leave" is fine.

### Check 3 — Open PRs needing attention

```bash
gh pr list --author @me --state open --json number,title,url,statusCheckRollup,mergeable
```

For each open PR:

- Surface: title, CI status, mergeability, review state.
- Offer per PR: `/ro:gh-ship` to drive it forward / leave for review / close.

### Check 4 — In-flight branch tracked as a GH issue?

```bash
git branch --show-current
gh issue list --search "<branch-keywords>" --state all --limit 5
```

If the current branch's work isn't represented by an open GH issue (and the repo has a gh remote):

- Ask: "this branch's work — is it captured in an issue?"
- If no: offer to create one inline (`/ro:write-a-prd --target gh` for a feature, or a quick `gh issue create` for a bug).
- If yes but not labelled `ready-for-agent`: offer to label it.

### Check 5 — Chat-only decisions

The reflective check. Ask the user directly:

> "Looking back at this session — was there anything decided in conversation that isn't yet in code, an ADR, a GH issue, a Jira ticket, a Confluence page, a CONTEXT.md entry, or a wiki page?"

If yes, for each decision:

- Offer the right durable home based on audience:
  - **ADR** — hard-to-reverse architectural decision (create `docs/adr/000N-*.md` inline)
  - **CONTEXT.md** — domain language
  - **GH issue** — internal action item (Skip/Ronan implementation queue)
  - **Jira ticket (DAFO)** — partner-visible action item or research request (Taskforce, Bernt, Guy, Quint, or anything they need to see/agree on). Use `/ro:jira create`
  - **Confluence page** — partner-shared research, agreement, or RFC. Use `/ro:confluence create`
  - **Wiki page** — reusable knowledge worth carrying across projects
- Skill drafts the entry and asks user to approve before writing.

**Partner-visibility heuristic** — auto-suggest Jira/Confluence routing when:

- This session mentioned Taskforce, Bernt, Guy, Quint, or Dataforce
- Working directory is under `~/Dev/ai-projects/dataforce*`
- The decision involves an agreement, a deliverable, or research that partners need to verify

When that fires, the Atlassian options (`/ro:jira create`, `/ro:confluence create`) jump to the top of the destination list. Internal-only decisions still default to GH issue.

If the user can't recall, prompt with categories: "anything about architecture? domain terms? scope changes? things you tried and rejected? anything Taskforce should see?" Memory `feedback_call_out_assumptions.md` — do not invent decisions; if the user says nothing material happened, accept that.

### Check 5b — DAFO tickets needing a status move

Skip unless the session touched the `dataforce` repo or any DAFO ticket was referenced in chat.

If it did:

- Ask: "any DAFO tickets that should move based on what shipped this session?"
- For each: offer `/ro:jira move <KEY> "In Review"` (PR merged, not yet live) or `/ro:jira move <KEY> done` (live in production — the strict rule from the partnership chat).
- If a Confluence page was authored this session that links to a DAFO ticket, offer to mirror the link the other way via `/ro:confluence link`.

This check enforces the partnership convention: Jira reflects partner-facing state, and the move to Done only happens when shipped.

### Check 6 — New domain terms in CONTEXT.md?

Skill scans for capitalised domain-sounding nouns in this session's git diffs and conversation that aren't already in `CONTEXT.md`:

```bash
grep -Eo '\b[A-Z][a-zA-Z]+\b' <session-touched-files> | sort -u
# diff against CONTEXT.md term list
```

If candidates surface:

- Ask per term: is this a new domain concept worth glossarising? (Skip generic programming nouns.)
- If yes: append to `CONTEXT.md` under `## Language` with a one-sentence definition. Use the format in [grill-with-docs/CONTEXT-FORMAT.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/grill-with-docs/CONTEXT-FORMAT.md).

### Check 7 — Vault ROADMAP / log staleness

If the session touched a vault under `vaults/<name>/`:

- Read `vaults/<name>/ROADMAP.md`. Did anything move (`In progress` → `Recently completed`)? Anything new in `Next up`?
- Read `vaults/<name>/log.md`. Is the tail entry for today's session?
- Offer to invoke `/ingest session --vault <name>` to do this properly. That skill writes the session source-note, appends ROADMAP, appends log.md, and routes graduate-worthy knowledge to Hub vaults.

`--vault <name>` flag forces a specific vault; otherwise auto-detect by working directory or by files touched this session.

### Check 8 — Memory entries worth saving

The kind of thing that earns a memory entry (per the auto-memory rules):

- User explicitly said "remember X" / "save this"
- User corrected something I did, and the correction is non-obvious / reusable
- User confirmed an unusual choice worked (validated judgment, worth keeping)
- A preference or constraint that should shape future sessions (deadline, naming, tool choice)

Ask: "Anything from this session worth saving as a persistent memory (feedback rule, project state, reference pointer, user fact)?"

If yes: skill drafts the memory entry (see `~/CLAUDE.md` § auto memory for types and structure), shows to user, writes to `~/.claude/projects/<project-slug>/memory/<file>.md` and appends to that project's `MEMORY.md` index. Per `feedback_call_out_assumptions.md`: do not invent. Only save what the user actually said or what is clearly load-bearing.

## Wrap-up summary

After all 8 checks, print a single-line status:

```
✓ Clean to clear context.
  • <N> commits pushed
  • <N> issues created
  • <N> ADRs written
  • <N> wiki pages updated (vault: <name>)
  • <N> memory entries saved
  • <N> items deliberately left (with reasons)
```

If anything's still open ("there's an uncommitted change you said leave for next session"), repeat it back so the user starts the next session knowing it.

## Flags

- `--quick` — run only checks 1, 2, 3 (mechanical state). Skip reflective + vault + memory. Use when you're not really closing, just stepping away briefly.
- `--reflective` — run only checks 5, 6, 8. Skip mechanical. Use when state is already clean but you want to capture knowledge.
- `--vault <name>` — force the vault routing in check 7 to a specific vault. Otherwise auto-detect.
- `--skip <n>` — skip a numbered check (repeatable, e.g. `--skip 4 --skip 6`).

## Why this exists

The LLM Wiki system is built around durable state: GH issues, ADRs, CONTEXT.md, wiki pages, ROADMAP, log, memory. The Pocock pattern operationalises that for project repos. But durability only works if there's a discipline that **moves the conversation's loose state into durable form before context clears**. Without it, even a perfectly-shaped system leaks knowledge every session.

This skill is the discipline.

## Related

- `[[ingest-session]]` — the vault-side counterpart; this skill delegates to it for check 7.
- `[[agentic-e2e-flow]]` — the start-of-session counterpart for feature work.
- `[[pickup]]` — the re-entry skill for vaults (project-side equivalent is on the roadmap).
- `[[agent-native-repo-pocock]]` — the pattern that makes durable state actually capture-able.
- `/ro:jira`, `/ro:confluence`, `/ro:jira-to-gh` — Atlassian capture surfaces invoked from Check 5 and Check 5b for partner-visible work.
