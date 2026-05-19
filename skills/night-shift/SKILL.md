---
name: night-shift
description: Autonomous overnight swarm against the current repo's GitHub backlog. Opens with an explicit scope grill (drain ready-only vs grill-drafts-first vs auto-slice-parents vs full-drain) so the user always knows what AFK means for this run. Loops wave-after-wave with a 4-signal ranker (age + priority + size + unblocks-others), hybrid file-area conflict detection between parallel workers, optional follow-up-issue creation, and an end-of-session nightsheet (GH issue + completion-report HTML) tap-throughable from Pushover/Telegram. Use when you want to kick off the night-shift swarm, drain the backlog, run AFK against GH issues, or "go to bed and wake up to PRs".
category: development
argument-hint: [--scope <ready-only|grill-first|auto-slice|full-drain>] [--max-waves <N>] [--max-runtime <duration>] [--workers <N>] [--label <label>] [--build swarm|ralph] [--no-followups] [--no-grill] [--no-ping] [--no-retro] [--plan-only] [--yes]
allowed-tools: Bash Read Write Edit Agent AskUserQuestion
---

# /ro:night-shift

The "swarm the factory" trigger. Run inside any repo with a `gh` remote and at least one `ready-for-agent` slice (or a draft PRD inbox if you want grill-first scope).

This is the shortest path between "I'm going to bed" and "the swarm is working", BUT the opening grill (US-0) makes "AFK" mean something explicit. Three AFK modes look identical from the couch and very different in the morning. Pick on purpose.

## Part of the local factory

`/ro:night-shift` is the AFK entrypoint to the **local factory** — the family of agent-loop skills that run autonomously on Ronan's machine. Siblings: `/ro:ralph`, `/ro:planner-worker` (alias `/ro:swarm`), `/ro:matt-pocock-coding-workflow`, `/ro:day-shift`. They share artefact shape (worker-scratch + harvested patterns + per-session aggregate), gitignore rules, and PR conventions. See `/ro:ralph` § "Run artefacts (the canonical shape)" for the canonical reference.

The companion is the **remote factory** — the Factory app (tracked separately) that runs equivalent loops as a cloud service. Story formats and PR conventions are compatible.

## What it does at a glance

1. **Opening grill (US-0).** Asks four questions about scope, looping, follow-ups, and caps so the user knows exactly what they're authorising. Skipped by `--yes` or `--no-grill` plus the relevant flag overrides.
2. **Rank the queue (US-1).** 4-signal weighted score: age, priority label, size/scope, unblocks-others count. Top of the ranked queue runs first.
3. **Build the dep + file-area graph (US-2).** Hybrid static (read slice bodies for declared paths) plus a probe-scout fallback if the first wave hits cross-worker merge conflicts.
4. **Dispatch a wave (US-3).** Up to `--workers N` parallel agents in git worktrees, no two on overlapping file-areas, no two violating `## Blocked by` deps. Calls `/ro:planner-worker --skip-grill --queue <ranked-file>`.
5. **Wait for the wave.** All workers either merge clean or escalate. Merger is Opus 4.7.
6. **Re-rank and re-dispatch (US-4).** If the queue still has unblocked work, run another wave. Loop until terminator.
7. **Queue refill (US-5).** When the ready queue empties, refill per scope: auto-slice the next parent PRD via a planner sub-agent, grill a `prd:draft`, or stop.
8. **Workers may open follow-up issues (US-6).** Out-of-scope TODOs surfaced mid-implementation become new `ready-for-agent` issues labelled `nightshift-followup` so they get triaged the next morning, not dropped.
9. **Nightsheet (US-7).** End-of-session aggregate: a GH issue labelled `nightsheet` summarising what shipped, what's open, what's blocked, plus a `/ro:completion-report` HTML on disk.
10. **Retro (Phase 7, see below).** `/ro:night-shift-retro` runs after the swarm exits, captures matrix-row failures and failure modes per slice, files SYSTEM action items against ronan-skills / factory, files PROJECT action items against the current repo as `ready-for-human`, writes a markdown + JSON artefact under `.nightshift/retros/<date>-<run-id>.{md,json}`. Pushover and Telegram fire AFTER the retro so the notification URL deep-links into the retro markdown.

## US-0: Opening grill — what does AFK mean tonight?

Unless `--yes`, `--no-grill`, or all four scope flags are passed explicitly, the skill opens with four `AskUserQuestion` gates. Each has a project-aware recommendation derived from the current queue state.

**Probe up front** (before asking anything):

```bash
gh issue list --label ready-for-agent --state open --search "-label:prd:draft" --json number,body,labels --limit 200 > /tmp/nightshift-ready.json
gh issue list --label prd:draft --state open --json number,title,updatedAt --limit 50 > /tmp/nightshift-drafts.json
# slices vs parent PRDs by body shape:
#   slice  body opens with `## Parent\n\n#<N>`
#   parent body opens with `## Problem Statement`
jq '[.[] | select(.body | startswith("## Parent\n\n#"))] | length' /tmp/nightshift-ready.json   # N_slices
jq '[.[] | select(.body | startswith("## Problem Statement"))] | length' /tmp/nightshift-ready.json  # N_parents
jq 'length' /tmp/nightshift-drafts.json                                                              # N_drafts
```

### Question 1 — Scope

> "What's the scope for this night-shift run?"

| Option | What it does | When recommended |
|---|---|---|
| `ready-only` | Drain only existing `ready-for-agent` slices. Stop when empty. No grilling, no slicing. | When `N_slices >= 3` AND `N_parents == 0` AND `N_drafts == 0`. The pure-drain happy path. |
| `grill-first` | Grill each `prd:draft` into a Pocock 7-section parent, then slice each parent, then drain. | When `N_drafts >= 1`. Adds 5-15 min per draft before workers fire. |
| `auto-slice` | Slice any open parent PRDs (`## Problem Statement` body) into child slices, then drain. Skips drafts. | When `N_parents >= 1` AND `N_drafts == 0`. |
| `full-drain` | Everything: grill drafts → slice parents → drain. Closes the most issues. | When the user says "I want to see all issues closed tomorrow" or `N_drafts + N_parents >= 2`. |

CLI: `--scope ready-only|grill-first|auto-slice|full-drain`.

### Question 2 — Loop until empty, or single wave?

> "Drain in one wave, drain the whole queue, or loop indefinitely?"

| Option | What it does | When recommended |
|---|---|---|
| `single-wave` | Dispatch exactly one wave of workers (up to `--workers N`). Exit when wave returns. | Sanity-check runs, lunch-break swarms. |
| `drain` | Multiple waves until ready queue is empty. Default. | The night-shift default. |
| `indefinite` | Drain + refill (per scope) + drain + refill until `--max-waves` or `--max-runtime` cap. | "Wake up to an empty backlog" + `full-drain` scope. |

CLI: `--max-waves N` (default 20 for `indefinite`, 6 for `drain`). `--max-runtime` (default 8h).

### Question 3 — Workers permitted to open follow-up issues?

> "If workers hit an out-of-scope TODO mid-implementation, should they open a follow-up GH issue?"

| Option | What it does | When recommended |
|---|---|---|
| `yes` | Workers may `gh issue create --label ready-for-agent --label nightshift-followup` for adjacent work they find. Listed in the morning nightsheet. | Default. Backlog grows by maybe 0-5 issues per wave; you triage in the morning. |
| `no` | Workers stay strictly on-task; out-of-scope TODOs are dropped on the floor. | When you want a quiet morning queue. |

CLI: `--no-followups` to suppress.

### Question 4 — Caps?

> "Workers cap and max runtime?"

| Field | Default | Notes |
|---|---|---|
| `--workers` | `min(3, floor(cores/2))` | Max plan tier: keep <=3 to stay under weekly cap. Hard ceiling 10 without `--unsafe-many`. |
| `--max-runtime` | `8h` | Wall-clock cap, the swarm exits cleanly at the cap regardless of queue state. |
| `--max-waves` | `6` for `drain`, `20` for `indefinite` | Belt-and-braces stop. |

Each answer is echoed back as the equivalent CLI flag. The full set of flags forms a one-line repeatable invocation for next time.

### `--yes` / `--no-grill` shortcut

Skips US-0 entirely. Uses defaults: `--scope ready-only`, `--workers 3`, `--max-waves 6`, `--max-runtime 8h`, follow-ups ON. This is the original zero-config behaviour; explicit now so users opt in.

### Filter / scope: `prd:draft` is NEVER auto-picked

`prd:draft` issues are NEVER picked up as work by this skill UNLESS `--scope grill-first` or `--scope full-drain` is selected. In those scopes drafts are picked up by the grill phase, not the worker dispatch — they get rewritten into Pocock parents BEFORE any worker sees them.

Defence in depth on the ready-queue query:

1. `gh issue list --label ready-for-agent --search "-label:prd:draft" ...` (server-side exclude).
2. Post-filter the JSON: drop any `labels[].name == "prd:draft"`.
3. Only consider issues whose body opens with `## Parent\n\n#<N>` as slices (parents have `## Problem Statement`).

## US-1: Rank the queue

4-signal weighted score. Higher = run first. Weights are tuneable via `.swarm.json` `ranking.weights` but ship as:

```yaml
ranking:
  weights:
    age: 1.0              # days since open, normalised 0..1 across queue
    priority: 2.0         # P0=1.0, P1=0.66, P2=0.33, unset=0
    size: 1.5             # smaller first: S=1.0, M=0.5, L=0.0 (parsed from `estimate:` body field)
    unblocks: 2.5         # count of OTHER open issues whose `## Blocked by` references this issue, normalised
```

`score = sum(weight[i] * normalised_signal[i])`. Ties broken by issue number (lower first).

**How signals are read:**

- **age** — `gh` `createdAt` minus now.
- **priority** — labels starting with `priority:` or matching `P[0-9]`. Repos without priority labels get 0 for all.
- **size** — slice body's `estimate:` frontmatter or `## Size` section. If missing, infer from line-count of touched-paths declared in the body (1-2 paths = S, 3-6 = M, >6 = L). If body doesn't declare paths, default M.
- **unblocks** — build the reverse `Blocked by` graph from all open slices; this signal is the count of issues this one unblocks if closed.

The ranked queue is written to `.swarm/ranked-queue.md` as a Markdown table with scores, used by all subsequent waves and printed to the user pre-dispatch.

## US-2: Build the dep + file-area graph (hybrid conflict detection)

Two graphs, both consulted before any wave:

### Dep graph (static, always)

Parse `## Blocked by` sections in each slice body. Edges from blocker → blocked. Workers may only dispatch when all blockers are merged.

### File-area graph (hybrid: static first wave, probe-scout if conflicts appear)

**Static pass (wave 1):**

Read each slice body for any of these:
- A `## Files touched` or `## Touches` section listing paths.
- Inline mentions matching `src/...`, `app/...`, `apps/...`, `packages/...`, `drizzle/...`, etc.
- An `estimate:` frontmatter block with a `paths:` list.

Build an undirected affinity graph: two slices share an edge if their declared path sets intersect by file or by directory at depth >=2 (e.g. `src/routes/settings.tsx` and `src/routes/settings.test.ts` share `src/routes/`). Two slices sharing an edge are **never dispatched in the same wave**.

**Scout pass (only if wave 1 had cross-worker merge conflicts):**

After a wave reports any merger-stage conflict between two workers' branches (i.e. rebase-onto-staging conflict), promote conflict detection: spawn a scout `Agent` per remaining slice with this prompt:

```
You are a SCOUT sub-agent for /ro:night-shift.

Slice: <issue body inlined>

Task: read the slice and predict the SET of file paths the implementation will touch.
Output a JSON object on stdout, nothing else:
  {"paths": ["src/routes/...", "src/lib/..."], "confidence": "high|medium|low"}

Rules:
- Do not edit anything.
- Do not run pnpm install or any side-effects.
- Read the codebase enough to be accurate. ~2-3 min budget.
- If you cannot tell, output paths: [] with confidence: low — the planner will assume worst case.
```

Scout outputs are merged into the file-area graph for waves 2+.

CLI: `--no-scout` disables scout pass entirely (purely static).

## US-3: Wave dispatch

For each wave:

1. From ranked queue, peel issues in score order that satisfy: deps met AND no file-area overlap with already-peeled-this-wave AND `status != stuck`. Stop when wave hits `--workers N`.
2. Dispatch via `/ro:planner-worker --skip-grill --queue .swarm/wave-<N>.md` (passes the peeled slice IDs through).
3. The planner-worker run handles its own US-1 .. US-14 inside the wave: worktree per worker, DoD, merger Opus 4.7, escalation on conflict.
4. Wait for the wave to fully resolve (all merged or escalated). Re-read open issues from GH (workers may have opened follow-ups, see US-6).
5. If queue still has unblocked work, goto wave N+1. Else, drop into US-5 refill.

Wave summary appended to `.swarm/nightshift-status.md` after each wave.

## US-4: Refill when ready queue empties

Branch on `--scope`:

- **`ready-only`** — exit clean. Print "ready queue drained, N waves, M PRs merged, K escalated."
- **`auto-slice`** — pick the top-ranked open parent PRD (body opens with `## Problem Statement`, has the `ready-for-agent` label). Dispatch `/ro:slice-into-issues --prd <parent-number>` (publishes child slices as GH issues, body `## Parent\n\n#<parent-number>`). When new slices appear, goto US-1.
- **`grill-first`** — pick the top-ranked open `prd:draft`. Dispatch `/grill <draft-number>` (rewrites the body into Pocock 7-section and the user/skill swaps `prd:draft` for `ready-for-agent`). Then goto US-4 again — the newly-grilled parent now needs slicing.
- **`full-drain`** — grill all drafts first, then slice all parents, then drain. Iterate: drain → slice next parent → drain → slice next → ... → grill next draft → slice → drain → ... → exit when no drafts, no parents, no slices.

All refill phases are bounded by `--max-waves` and `--max-runtime`. When a cap is hit, the loop exits cleanly via US-7 nightsheet, no half-merged worktrees left behind.

## US-5: Workers may open follow-up issues

Unless `--no-followups`, every worker's dispatch prompt gets appended:

```
You may open ONE follow-up GH issue per slice you complete IF you encounter
a clearly-out-of-scope TODO that is:
  - in the same area of the codebase
  - small enough to be a future vertical slice (S or M)
  - not already an open issue (check with `gh issue list --search "<topic>"`)

If you open one, do it with EXACTLY:
  gh issue create \
    --label ready-for-agent --label nightshift-followup \
    --title "<one-line>" \
    --body "<followup-body with ## Parent #<source-slice> if relevant, plus ## Blocked by None>"

Then continue with your assigned slice. Follow-ups DO NOT count as a DoD item.
```

Follow-ups are visible to the next wave's ranker (they're now part of the ready queue) but the rank is age-based so they sort below older work.

## US-6: Nightsheet at end of session

On final exit (clean drain, max-waves hit, max-runtime hit, or fatal error), the skill ALWAYS writes a nightsheet via TWO outputs:

### Output A — GH issue with `nightsheet` label

```bash
gh issue create \
  --label nightsheet \
  --title "Night shift $(date -u +%Y-%m-%dT%H:%M) — <N> merged, <M> escalated, <K> follow-ups" \
  --body "$(cat .swarm/nightsheet-<ts>.md)"
```

Body template:

```markdown
# Night shift run <ISO8601 start> → <ISO8601 end>

**Scope:** <scope> | **Waves:** <N> | **Duration:** <duration>

## Merged PRs (<N>)
- #<pr> — <title> (slice #<issue>)
...

## Escalated (<M>)
- #<pr> — <title> — <one-line cause> — worktree: .swarm/worktrees/<id>
...

## Follow-up issues opened (<K>)
- #<issue> — <title> — opened by worker on slice #<source>
...

## Drafts grilled (<G>)
- #<issue> — <title> — parent now #<parent-issue>
...

## Parents sliced (<P>)
- #<parent> — sliced into <X> children: #<a>, #<b>, ...
...

## Blockers carrying over to tomorrow
- #<issue> — blocked by #<other>
...

## Ranked queue at exit
| score | issue | title | reason |
|--- |--- |--- |--- |
| 0.81 | #234 | settings page polish | top: high unblocks-others, P1 |
...

## Completion report
- Local HTML: `<repo>/.completion-reports/<ts>-<slug>.html`
- Open with: `open <path>`
```

### Output B — completion-report HTML

```bash
/ro:completion-report --prs "<merged-pr-list>" --title "night-shift-<ts>" --no-open
# capture the printed path
```

### Pushover + Telegram with deep link

Per global `~/CLAUDE.md` rule 4 (Pushover) and the Telegram sibling rule, fire BOTH:

```bash
bash ~/Dev/ronan-skills/skills/pushover/scripts/notify.sh \
  "night shift done: <N> merged, <M> stuck, <K> follow-ups" \
  --title "Night shift" \
  --url "file://<completion-report-path>"

bash ~/Dev/ronan-skills/skills/telegram/scripts/notify.sh \
  "night shift done: <N> merged, <M> stuck, <K> follow-ups" \
  --title "Night shift" \
  --url "file://<completion-report-path>"
```

Tapping either notification opens the HTML diff browser. The nightsheet GH issue is the durable triage queue for the morning.

Skip BOTH notifications only when `--no-ping` or `--plan-only`.

## US-7 (Phase 7): Run retro

After the swarm exits (clean drain, max-waves, max-runtime, or fatal error) AND after the nightsheet GH issue + completion-report HTML are written, BUT BEFORE the Pushover + Telegram pings fire:

```bash
/ro:night-shift-retro --run-id "$run_id" --dispatcher night-shift
```

The retro:

1. Reads `.swarm/nightsheet-*.md`, `.swarm/run-*.md`, `.swarm/status.md`, `.swarm/logs/*.log`, and `gh pr list --search "merged:>=$started_at"` to reconstruct the run.
2. Classifies each slice's outcome (`merged` / `blocked` / `deferred` / `auto-split`) and failure mode (`thrashing` / `proxy-gaming` / `misalignment` / `non-convergence` / `context-drift` / `runaway-resource` / `other`).
3. Drafts action items, classified `SYSTEM` (ronan-skills / factory) vs `PROJECT` (current repo, `ready-for-human` label) vs `UNCLEAR` (markdown only).
4. Writes `.nightshift/retros/<YYYY-MM-DD>-<run-id>.md` + `.json`.
5. Files cross-repo issues per the routing rules in [[night-shift-retro-and-day-shift]] § "Cross-repo routing" when `.ronan-skills.json` `retros.open_followup_issues: true`.
6. Drops the retro URL into `.nightshift/last-retro-url.txt` so the subsequent Pushover + Telegram tail call can deep-link into it.

The Pushover + Telegram pings (US-6 above) THEN fire with `--url file://<retro-path>` instead of just the completion-report HTML — tapping the phone notification lands in the retro markdown, which links back to the completion-report HTML and the nightsheet issue.

Skip the retro under any of:

- `--no-retro` (explicit skip)
- `--plan-only` (nothing ran)

`--no-ping` does NOT skip the retro; it only skips the notification. The retro artefact is always written when work happened.

See `/ro:night-shift-retro` for the full skill definition.

## Defaults inherited from ronan-skills ≥ 1.56.x

- `--source github:<label>` — read from current repo's GH backlog (passed through to `/ro:planner-worker`)
- Opus 4.7 merger (planner-worker default)
- `--afk` semantics: auto-approve config inside each wave, judge-agent termination per wave, skip grilling per wave
- `--workers 3` cap unless overridden
- Pushover + Telegram at end per global CLAUDE.md rule 4

Override any by passing the flag explicitly.

## Quick start

```bash
# Interactive: opens the four-question grill, then runs
/ro:night-shift

# Ready-queue drain, no questions
/ro:night-shift --scope ready-only --yes

# Full overnight: grill drafts + slice parents + drain
/ro:night-shift --scope full-drain --max-runtime 8h --max-waves 20

# Auto-slice open parent PRDs and drain, but don't touch drafts
/ro:night-shift --scope auto-slice

# Serial Ralph instead of parallel swarm (use when slices are dep-chained)
/ro:night-shift --build ralph

# Smaller crew (Max plan weekly cap considerate)
/ro:night-shift --workers 2

# Custom queue label (Pocock synonym example)
/ro:night-shift --label Sandcastle

# Dry-run: print what would dispatch, no actual work
/ro:night-shift --plan-only

# Silent: skip the notification
/ro:night-shift --no-ping

# No retro artefact (still pings)
/ro:night-shift --no-retro
```

## When NOT to use

- **No GH remote.** `/ro:night-shift` requires a gh remote. Run `gh repo create` or use the local-file flow via `/ro:planner-worker --prd <name>` directly.
- **No backlog AND no drafts AND no parents.** Run `/ro:write-a-prd` and `/ro:slice-into-issues` first, or use `/agentic-e2e-flow` for the full pipeline.
- **First time in a repo with unknown config.** The opening grill handles this, but if you also want to grill on worker count, judge-agent, etc., run `/ro:swarm` directly the first time, then come back here.
- **Single-story exploration.** Use `/ro:ralph --mode single`.
- **Untrusted code or hostile input.** No container isolation; the cloud factory at `github.com/RonanCodes/factory` is the sandboxed path (see [skill-lab:factory-overnight-coding-swarm](obsidian://open?vault=llm-wiki-skill-lab&file=wiki%2Fpatterns%2Ffactory-overnight-coding-swarm)).

## Errors

| Condition | Message |
|---|---|
| No gh remote | "Not in a gh-remote repo. `/ro:night-shift` requires a GitHub remote. Run `gh repo create` to add one." |
| Empty ready queue + no drafts + no parents | "No `<label>` slices, no `prd:draft` drafts, no open parent PRDs. Run `/ro:write-a-prd` + `/ro:slice-into-issues` to populate the backlog (or use `/agentic-e2e-flow` for the full pipeline)." |
| Empty ready queue + drafts exist but scope=ready-only | "No ready slices, but you have N `prd:draft` issues. Re-run with `--scope grill-first` or `--scope full-drain`, or run `/ro:list-draft-prds` to see them." |
| Empty ready queue + parents exist but scope=ready-only | "No ready slices, but you have N open parent PRDs that haven't been sliced. Re-run with `--scope auto-slice` or `--scope full-drain`, or run `/ro:slice-into-issues --prd <N>` manually." |
| All slices blocked by escalations | "All `<label>` slices are blocked, by: #N, #M, #K. Resolve those first or unblock manually." |
| Max-waves hit | "Hit `--max-waves <N>` cap. Nightsheet written to issue #<N>. Resume with `/ro:night-shift --scope <same>`." |
| Max-runtime hit | "Hit `--max-runtime <duration>` cap. Nightsheet written to issue #<N>. Resume with `/ro:night-shift --scope <same>`." |
| Build flag `--build ralph` with parallel-eligible slices | "Heads-up: most slices look parallel-eligible. `--build swarm` would finish faster. Continue with serial Ralph? (y/N)" — auto-continue if `--yes`. |

## How this composes with related skills

- **`/ro:planner-worker` (alias `/ro:swarm`)** — night-shift wraps it. Planner-worker is one wave; night-shift is the multi-wave drain + refill loop with the explicit-scope grill on top. Use planner-worker directly when you want a single wave or a different PRD source.
- **`/ro:ralph`** — alternative serial build inside a wave via `--build ralph`. Use when slices are dep-chained (mostly linear `Blocked by` graph).
- **`/ro:write-a-prd`** — upstream PRD writer. Night-shift's `--scope grill-first` / `--scope full-drain` triggers a grill on existing `prd:draft` issues but does not invent new PRDs.
- **`/ro:slice-into-issues`** — invoked by `--scope auto-slice` and `--scope full-drain` to break parent PRDs into child slices mid-loop.
- **`/grill` (grill-with-docs)** — invoked by `--scope grill-first` and `--scope full-drain` to promote drafts into Pocock parents.
- **`/agentic-e2e-flow`** — the full end-to-end pipeline if you also want the swarm-research and grill-with-docs phases upstream. Night-shift is the "I already have a backlog, just drain it" subset.
- **`/ro:completion-report`** — invoked at end of session to build the HTML deep link.
- **`/ro:night-shift-retro`** — Phase 7 sibling; captures SYSTEM/PROJECT action items + the markdown+JSON retro artefact deep-linked from Pushover/Telegram.
- **`/ro:day-shift`** — morning sibling; grills the backlog into shape for tonight's run. Pair these two for the full async chain (see [[night-shift-retro-and-day-shift]]).
- **`/ro:pushover` + `/ro:telegram`** — fired at end per global CLAUDE.md rule 4.

## Provenance

- **2026-05-14** — created in response to "I want a forward slash command that auto runs the night-shift swarm with sub-agent planners and sub-agent workers against the existing GH backlog for the current repo." Built on top of `/ro:planner-worker` and the auto-pushover + Opus-reviewer defaults locked in ronan-skills 1.46.1.
- **2026-05-19** — major rewrite. Added explicit-scope opening grill (US-0), 4-signal ranker (US-1), hybrid file-area conflict detection (US-2), indefinite drain + refill loop (US-3, US-4), worker follow-up issues (US-5), nightsheet (US-6). The trigger that motivated this: "I want to see all issues closed tomorrow", which made the zero-config single-wave behaviour insufficient. Also: making "AFK" mean three different things (ready-only / grill-first / full-drain) and forcing the user to pick once at the start of the run.

See also: [skill-lab:factory-overnight-coding-swarm](obsidian://open?vault=llm-wiki-skill-lab&file=wiki%2Fpatterns%2Ffactory-overnight-coding-swarm) for the cloud-deployed sibling running on Pi + Cloudflare Sandbox.
