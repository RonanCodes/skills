---
name: day-shift
description: Morning bridge skill that shapes the GitHub backlog between night-shift runs. Partitions open issues into buckets (prd:draft, ready-for-human, blocked-on-human, swarm, needs-triage), grills candidates one round at a time via AskUserQuestion (Pocock's grill-with-docs flow), promotes successfully grilled issues to the swarm gate label, and escalates non-converging issues to blocked-on-human with a structured comment naming the explicit human action needed. Defers to /ro:repo-mode (work mode reads .ralph/issues/ instead). Use in the morning after /ro:night-shift, before chaining grill → PRD → slice → ralph via /ro:matt-pocock-coding-workflow.
category: development
argument-hint: [--repo <path>] [--all-repos <glob>] [--max-rounds 3] [--escalate-label blocked-on-human] [--gate-label swarm] [--dry-run]
allowed-tools: Bash Read Write Edit Glob Grep AskUserQuestion
---

# /ro:day-shift

The morning sibling to `/ro:night-shift`. Where night-shift drains the backlog and writes a retro, day-shift shapes the backlog for the next drain. Manual invocation only in v1 — no cron, no auto-trigger. The user owns when to do the morning pass.

The skill exists because issues silently park. A `prd:draft` that no one grills becomes a permanently stale parent. A `ready-for-human` that no one resolves becomes a black hole. A `swarm`-labelled issue missing the close-the-loop AC block becomes a guaranteed broken merge tomorrow night. Day-shift forces a five-minute morning pass that names the human action needed for each parked issue.

See [[night-shift-retro-and-day-shift]] for the async chain this skill sits inside.

## When invoked

- Morning after a `/ro:night-shift` run, before the user plans the day.
- Phase 6 of `/ro:matt-pocock-coding-workflow` (auto-invoked there).
- Any time the backlog feels stale ("why hasn't this moved").
- Multi-repo morning pass (`--all-repos`) when running multiple agent-native repos in parallel.

Skip when:

- The repo has no `gh` remote AND is not in work mode (no backlog source).
- The user just ran day-shift in the last hour (idempotent but wasteful).

## Quick start

```bash
# Default: current repo, max 3 grill rounds per issue, real changes
/ro:day-shift

# Dry run: print partition + intended promotions / escalations, no writes
/ro:day-shift --dry-run

# Multiple personal repos in one morning pass
/ro:day-shift --all-repos "~/Dev/ai-projects/{dataforce,lekkertaal,factory}"

# Tighter grill (1 round, fewer questions)
/ro:day-shift --max-rounds 1

# Repo with a project-specific gate label (Pocock's Sandcastle convention)
/ro:day-shift --gate-label Sandcastle
```

## US-0: Resolve repo mode + label set

Run the [[repo-mode]] 4-line resolution. Behaviour branches:

- `personal` — read backlog via `gh issue list`, write label transitions via `gh issue edit`, post comments via `gh issue comment`
- `work` — read `.ralph/<name>/issues/*.md`, write frontmatter transitions to the same files, append decision notes to a sibling `.ralph/<name>/day-shift.log`

Resolve the gate label (the synonym for `ready-for-agent`):

```bash
# Default
gate_label="${ARG_GATE_LABEL:-swarm}"

# Read project synonym from docs/agents/triage-labels.md if present
if [ -f docs/agents/triage-labels.md ]; then
  synonym=$(grep -oE 'ready-for-agent.*spelled.*`[A-Za-z0-9_-]+`' docs/agents/triage-labels.md | grep -oE '`[A-Za-z0-9_-]+`$' | tr -d '`')
  [ -n "$synonym" ] && gate_label="$synonym"
fi
```

Common shapes: `swarm` (dataforce), `Sandcastle` (Pocock's reference repo), `ready-for-agent` (generic).

## US-1: Pull the backlog and partition

```bash
gh issue list --state open --json number,title,body,labels,createdAt,updatedAt --limit 200 > /tmp/day-shift-backlog.json
```

Partition each issue into one of:

| Bucket | Detection |
|---|---|
| `needs-grilling` | Has `needs-grilling` (canonical) OR legacy `prd:draft` label OR body opens with anything other than `## Problem Statement` / `## Parent\n\n#<N>` AND has no gate label |
| `needs-human` | Has `needs-human` (canonical) OR legacy `ready-for-human` / `blocked-on-human` label |
| `swarm` | Has the gate label (resolved in US-0; typically `ready-for-agent`) AND no `needs-grilling` / `needs-human` |
| `needs-triage` | None of the above |

The order matters: an issue with both `needs-grilling` and the gate label is `needs-grilling` (mislabelled drift; the grill below will fix it).

This skill is the canonical home of the `needs-grilling → ready-for-agent` transition per the canonical label system (`~/Dev/ronan-skills/canon/labels.md`). When the grill converges, swap labels in one call:

```bash
gh issue edit <num> --add-label ready-for-agent --remove-label needs-grilling
```

If the user explicitly bypasses the grill ("skip" / "ship it"), use:

```bash
gh issue edit <num> --add-label ready-for-agent --add-label needs-grilling-skipped --remove-label needs-grilling
```

so the reviewer knows the ACs may be thinner.

Print the partition as a one-screen summary:

```
Backlog partition (<N> open issues):

  needs-grilling    <K>  — need grilling into Pocock 7-section
  ready-for-human   <K>  — need a user action (resolvable now?)
  needs-human       <K>  — need an external unblock (still blocked?)
  swarm             <K>  — gate-labelled; verify AC matrix
  needs-triage      <K>  — new / unlabelled

Promote candidates (with --max-rounds <N>): <needs-grilling + needs-triage + (needs-human if user resolves)>
```

## US-2: For each `swarm`-bucket issue, verify the AC matrix

Refuse-to-dispatch behaviour mirrors `/ro:planner-worker` US-2a. For each `swarm`-bucket issue, check that the body contains the close-the-loop AC block:

```bash
issue_body="$(gh issue view "$NUM" --json body --jq .body)"
if ! grep -q '^### Close-the-loop tests' <<< "$issue_body"; then
  if ! grep -q '^### Close-the-loop verification matrix' <<< "$issue_body"; then
    flip_label "$NUM" --remove "$gate_label" --add "needs-info"
    gh issue comment "$NUM" --body "$(missing_acs_comment $gate_label)"
  fi
fi
```

`missing_acs_comment` body:

```markdown
## Day-shift: missing close-the-loop AC block

This issue is labelled `$gate_label` but the body does not contain a `### Close-the-loop tests` or `### Close-the-loop verification matrix` section.

Per [[close-the-loop-tests-acs]] + [[close-the-loop-verification-matrix]], the night-shift swarm refuses to dispatch a worker against a slice missing the AC block. To re-label as ready:

1. Re-run `/ro:slice-into-issues --prd <parent>` against the parent PRD (the slicer auto-emits the block), OR
2. Hand-edit this issue body to append the AC block from `/ro:slice-into-issues` § "Body template — Matt Pocock's slice shape", THEN
3. Re-add the `$gate_label` label and remove `needs-info`.

Day-shift flipped the label automatically so the next night-shift run doesn't dispatch against a leaky slice.
```

Flipping to `needs-info` keeps the issue visible but disqualifies it from the swarm queue.

## US-3: For each `prd:draft` and `needs-triage` candidate, grill

Walk Pocock's grill-with-docs flow, one question at a time, max `--max-rounds 3` per issue.

Round shape (one `AskUserQuestion` per round):

> **Round <N>/<max-rounds> for issue #<N> — <title>**
>
> Current body:
> ```
> <truncated body, max 30 lines>
> ```
>
> "What's the single most important question to resolve before this becomes a swarm-ready Pocock 7-section parent?"
>
> Options come from the user's free-text response; if the user defers ("not sure", "skip", "next"), advance to the escalation path.

After each round, propose an edit to the issue body that captures the answer. The body shape target is Pocock's 7-section (per [[agent-native-repo-pocock]]):

```markdown
## Problem Statement

## Solution

## User Stories

## Implementation Decisions

## Testing Decisions

## Out of Scope

## Further Notes
```

When all seven sections are present AND the user accepts the body → US-4 (promote).
When `--max-rounds` hit without all sections → US-5 (escalate to `blocked-on-human`).

## US-4: Promote successfully grilled issues to `swarm`

For each issue that passed the grill:

```bash
# Edit body to the grilled Pocock 7-section shape
gh issue edit "$NUM" --body-file /tmp/grilled-body-$NUM.md

# Append the agent brief comment with the close-the-loop matrix template
gh issue comment "$NUM" --body "$(agent_brief_with_matrix_template)"

# Flip labels
gh issue edit "$NUM" --remove-label "prd:draft" --remove-label "needs-triage" --add-label "$gate_label"
```

`agent_brief_with_matrix_template`:

```markdown
## Agent brief — close-the-loop matrix

This parent is ready for slicing. Each slice that the slicer emits MUST include the verbatim AC block below in its body (the slicer adds it automatically; this comment is the human-readable reminder).

### Close-the-loop verification matrix (REQUIRED, every slice)

- [ ] **Static:** typecheck + lint + format pass.
- [ ] **Unit:** new pure functions / Zod schemas / repo helpers have vitest coverage.
- [ ] **Integration:** any new API route is exercised via vitest with a mocked Nango / D1.
- [ ] **e2e:** any new user-facing UI route or flow has a Playwright spec at `e2e/<story-slug>.spec.ts` that walks the full input-to-completion path (not just "page renders").
- [ ] **OpenAPI:** if a new HTTP route was added, `pnpm openapi:check` produces zero diff.
- [ ] **Bruno:** if a new HTTP route was added, the Bruno collection has a request + example response + auth note.
- [ ] **Logging:** new server routes have `log.info` at entry; new catch blocks call `log.error`; new user-facing actions fire a `log.info` PostHog event named `object.verb`. No direct `console.*` / `Sentry.*` / `posthog.*` outside `src/lib/log.ts`.
- [ ] **CHANGELOG:** user-visible change has an entry.
- [ ] **Docs:** any setup / command / env change updates `README.md`, `docs/`, and `.dev.vars.example`.
- [ ] **ADR:** if the story made a hard-to-reverse decision, an ADR is committed under `docs/adr/`.
- [ ] **Migrations:** if the schema changed, a Drizzle migration is generated and applied locally.
- [ ] **Manual smoke:** the PR description includes a 30-second smoke checklist for the merger.

Per [[close-the-loop-verification-matrix]] (matrix definition) and [[close-the-loop-tests-acs]] (narrower AC enforcement).
```

## US-5: Escalate non-converging issues to `blocked-on-human`

When `--max-rounds` rounds elapse without convergence:

```bash
gh issue edit "$NUM" --add-label "$escalate_label" --remove-label "$gate_label" --remove-label "prd:draft"
gh issue comment "$NUM" --body "$(blocked_comment_for "$NUM" "$reason")"
```

`blocked_comment_for` body — the rule is to name ONE explicit human action:

```markdown
## Day-shift: blocked, needs human

After $max_rounds grill rounds I could not resolve the spec enough to promote this to `$gate_label`. The single concrete human action needed is:

**<one-of: DECISION / CREDENTIAL / EXTERNAL_SIGN_OFF / DESIGN_CHOICE>**

<one to three sentences naming the specific decision / credential / sign-off / design choice required>

When unblocked, remove `$escalate_label` and re-run `/ro:day-shift` (or invoke `/grill` directly on this issue) so it re-enters the grill queue.
```

Categories the grill should pick from:

- `DECISION` — a product / technical choice between explicit options
- `CREDENTIAL` — an OAuth registration, API key, secret rotation
- `EXTERNAL_SIGN_OFF` — a stakeholder approval, contract, legal
- `DESIGN_CHOICE` — a UI / UX call needing a comp or Figma reference

Never leave silently parked. If no category fits, use `DECISION` and describe the missing decision.

## US-6: For each `ready-for-human`, ask if resolvable now

```
> "Issue #<N> — <title> is labelled `ready-for-human`. Body excerpt:
>   <30-line truncated body>
>
>  Can you resolve this now?"
>
>  Options:
>    - Yes, resolve now → walk through inline (re-grill, file the missing creds, etc.)
>    - Defer → leave label as-is
>    - Re-classify as blocked-on-human → flip label + comment naming external unblock
```

This is the only "interactive batch" of the morning. Keep it bounded; if the user says "skip all", break out of the loop and leave them parked.

## US-7: For each `blocked-on-human`, verify still blocked

```
> "Issue #<N> — <title> has been `blocked-on-human` since <last comment date>. The unblock action was: <quote from last day-shift comment>.
>
>  Still blocked?"
>
>  Options:
>    - Yes, still blocked → leave as-is
>    - No, unblocked → flip to needs-triage and re-enter the grill queue on next day-shift
>    - No, won't happen → close with wontfix
```

The point: stale `blocked-on-human` rotting in the backlog for weeks is the silent failure mode. Forcing the question every morning surfaces "we've been waiting on this for 14 days, is it actually going to happen".

## US-8: Output summary

```
day-shift summary — $repo

Grilled:    <N> (promoted: <K>, escalated: <L>)
Promoted:   <K> (now eligible for tonight's swarm)
Escalated:  <L> (flipped to blocked-on-human with named action)
AC-failed:  <M> (flipped to needs-info; missing close-the-loop block)
Resolved:   <P> ready-for-human → eligible for tonight's swarm
Unblocked:  <Q> blocked-on-human → re-entered grill queue
Closed:     <R> (wontfix)
Unchanged:  <S>

Tonight's likely swarm queue: <K + P> slices

Run `/ro:night-shift` when ready.
```

## Multi-repo mode (`--all-repos`)

When `--all-repos <glob>` is passed:

```bash
for repo in $(eval echo "$ARG_ALL_REPOS"); do
  [ -d "$repo/.git" ] || continue
  echo "==> $repo"
  pushd "$repo" >/dev/null
  /ro:day-shift   # recursive invocation, single-repo path
  popd >/dev/null
done
```

The summary aggregates across all repos:

```
day-shift summary — multi-repo

dataforce:   grilled 3 (promoted 2, escalated 1), AC-failed 1
lekkertaal:  grilled 1 (promoted 1)
factory:     grilled 0, ready-for-human resolved 1

Total swarm queue across repos: 5 slices
```

## Errors

| Condition | Message |
|---|---|
| No gh remote (personal mode) | "Not in a gh-remote repo. `/ro:day-shift` needs a backlog source. For work-mode repos, set `.claude/repo-mode = work` and the skill reads `.ralph/issues/` instead." |
| `gh auth` failed | "gh CLI not authed. Run `gh auth refresh` and re-invoke." |
| No open issues | "Backlog is empty. Either you're done or you need `/ro:write-a-prd` to populate it." |
| Repo mode `unset` | Run [[repo-mode]] first-run prompt, persist, continue. |
| `--all-repos` glob matched zero repos | "Glob `<glob>` matched no directories. Pass a glob that resolves (e.g. `~/Dev/ai-projects/*`)." |

## Anti-patterns

1. **Batching grill questions.** `AskUserQuestion` is one-at-a-time for a reason. The user's first answer often reshapes the second question.
2. **Auto-promoting `ready-for-human` without confirmation.** The label exists because a human decision was missed. Confirm before flipping.
3. **Letting `blocked-on-human` rot.** US-7 is the daily reminder. Skipping it lets a 30-day-old block sit forever.
4. **Skipping the AC matrix check on `swarm` issues.** That's the load-bearing defence against [[close-the-loop-tests-acs]] / [[close-the-loop-verification-matrix]] leaks. Refuse-to-dispatch is the right default.
5. **Day-shift on the same backlog twice in a morning.** Idempotent but noisy; the second pass mostly re-asks the same questions.
6. **Treating `--all-repos` as "run everything overnight".** It's still interactive (each repo has grill rounds). Reserve for a focused 20-minute morning pass.

## See also

- [[night-shift-retro-and-day-shift]] — the pattern note describing the async chain
- `/ro:night-shift-retro` — the end-of-night sibling that wrote the action items day-shift may inherit as `ready-for-human` issues
- `/ro:night-shift` — the dispatcher day-shift shapes the backlog for
- `/ro:write-a-prd` — escalation path when an issue is too rough to grill (re-write from scratch)
- `/ro:slice-into-issues` — escalation path when a parent grilled cleanly but no slices exist yet
- `/ro:matt-pocock-coding-workflow` — Phase 6 invokes this skill
- `/grill` (grill-with-docs) — the underlying grill flow each round walks
- `/ro:list-draft-prds` — the inbox viewer; see what `prd:draft` issues exist before invoking day-shift

## Provenance

- **2026-05-19** — created alongside `/ro:night-shift-retro` and [[night-shift-retro-and-day-shift]] in response to the dataforce night-shift that shipped 11 PRs and surfaced one broken. The retro captured SYSTEM and PROJECT action items; day-shift was the missing morning step that turns "issue is parked with `ready-for-human`" into "issue is grilled and ready for tonight" or "issue is escalated to `blocked-on-human` with an explicit named action". The async chain depends on both halves running.
