---
name: night-shift-retro
description: End-of-run retrospective for autonomous swarm runs (night-shift, ralph --afk, planner-worker --afk, agentic-e2e-flow). Writes a sibling markdown + JSON artefact under .nightshift/retros/, captures matrix-row failures and failure modes per slice, files SYSTEM gaps as issues against ronan-skills or factory, files PROJECT gaps as ready-for-human issues against the current repo, and pings Pushover/Telegram with the retro URL as a deep link. Defers to /ro:repo-mode for personal vs work behaviour. Use at the end of every real autonomous run; auto-invoked by /ro:night-shift Phase 7 unless --no-retro is passed.
category: development
argument-hint: [--run-id <id>] [--commit-to-project|--no-commit] [--open-issues|--no-issues] [--repo <path>] [--dispatcher night-shift|ralph|planner-worker|agentic-e2e-flow]
allowed-tools: Bash Read Write Edit Glob Grep AskUserQuestion
---

# /ro:night-shift-retro

End-of-night SYSTEM/PROJECT retrospective. The bookkeeping skill that turns "11 PRs merged" into "11 PRs merged AND 3 ronan-skills issues filed AND 1 dataforce ready-for-human follow-up AND a JSON artefact the future cloud factory can ingest".

The retro exists because run-level signals (matrix-row failure shape, auto-split events, token burn rate per slice) die in the morning Slack window unless something captures them. The first time you skip the retro, the next regression hides until a human stumbles on it. See [[close-the-loop-verification-matrix]] for the matrix this retro tracks failures against and [[night-shift-retro-and-day-shift]] for the async chain it sits inside.

## When invoked

Fires automatically at the end of:

- `/ro:night-shift` (Phase 7, unless `--no-retro`)
- `/ro:ralph --afk` against a real backlog (not `--mode single`, not `--plan-only`)
- `/ro:planner-worker --afk` against a real backlog
- `/agentic-e2e-flow` against a real backlog

Skip when:

- The run was `--plan-only` (nothing actually ran)
- The run was single-story exploration (`/ro:ralph --mode single` standalone)
- The user explicitly passed `--no-retro` on the dispatcher

Invoke manually any time to reconstruct a retro from recent git + GH state (e.g. the orchestrator died mid-run and the retro never fired).

## Quick start

```
# Auto-invoked at end of /ro:night-shift; runs against the most recent run
/ro:night-shift-retro

# Reconstruct a retro from a specific run-id (must exist under .nightshift/runs/)
/ro:night-shift-retro --run-id 20260519-2330

# Generate retro but do NOT commit the markdown + JSON to the project
/ro:night-shift-retro --no-commit

# Generate retro and skip cross-repo issue creation (useful for dry-run)
/ro:night-shift-retro --no-issues

# Reconstruct against a different repo
/ro:night-shift-retro --repo ~/Dev/ai-projects/dataforce
```

## US-0: Resolve config + repo mode

Read `<repo>/.ronan-skills.json` for the `retros.*` block. Default shape if missing:

```json
{
  "retros": {
    "commit_to_project": "ask",
    "open_followup_issues": true,
    "auto_skill_retro": false
  }
}
```

`commit_to_project` first-run prompt via `AskUserQuestion` (header "Retros"):

> "Commit night-shift retro artefacts (markdown + JSON) under `.nightshift/retros/` to this repo?"
>
> Options:
> - **Yes** — retros are tracked. Useful for audit + future cloud-factory ingest.
> - **No** — retros live only in `.nightshift/` which gets gitignored. Useful for repos where the retro folder would create noise (work repos, throwaway prototypes).

Persist the answer to `.ronan-skills.json`. Subsequent runs use the persisted value.

Resolve repo mode via the [[repo-mode]] 4-line snippet. Work-mode behaviour:

- SYSTEM-bound action items still route to ronan-skills / factory (they're meta-tool repos, never the work GH/Jira/ADO project)
- PROJECT-bound action items skip the GH issue route and stay in the retro markdown only
- Retro artefacts go to `.nightshift/retros/` regardless of `commit_to_project`; gitignore them under work mode

## US-1: Gather run data

The retro's input is the orchestrator's run trail. Sources in order of preference:

1. `<repo>/.swarm/run-*.md` (planner-worker postmortem)
2. `<repo>/.swarm/nightsheet-*.md` (night-shift nightsheet)
3. `<repo>/.ralph/<name>.session.md` (ralph session log)
4. `<repo>/.swarm/status.md` (live state at exit)
5. `gh pr list --state merged --search "merged:>=<started-at>" --json number,title,body,mergedAt,mergeCommit` (PR side, ground truth)
6. `gh issue list --state closed --search "closed:>=<started-at>" --json number,title,labels` (issue side)
7. `<repo>/.swarm/logs/*.log` (per-worker logs — for failure-mode classification)

Cross-reference: every merged PR should map to a closed slice issue via `Closes #N`. Mismatches go in `failures[]` as `misalignment`.

If `--run-id` is given, scope the search to that timestamp window. Otherwise, walk back from the most recent dispatcher exit (look for the most recent `nightsheet-*.md` or `run-*.md`).

## US-2: Classify each slice

For each slice the run touched, classify the outcome:

| outcome | Definition |
|---|---|
| `merged` | PR merged, slice issue closed, matrix passed |
| `blocked` | Slice escalated to human; PR open or branch sitting |
| `deferred` | Slice picked but not finished (timed out, wave ended) |
| `auto-split` | Slice failed three attempts; planner re-decomposed into sub-slices (per [[close-the-loop-verification-matrix]] retry-and-split state machine) |

For each `blocked` or `auto-split` slice, classify the failure mode (use the per-slice prompt below if you can't tell from logs):

| mode | Symptom |
|---|---|
| `thrashing` | Same matrix row fails 3+ times across slices in this run |
| `proxy-gaming` | Tests passed but evidence shows the spec wasn't met (e.g. e2e asserts page renders, real flow loops) |
| `misalignment` | Worker built the wrong thing despite passing tests |
| `non-convergence` | Three attempts, all fail, no two failures look alike |
| `context-drift` | Late slice ships against an assumption from early slice that no longer holds |
| `runaway-resource` | Slice burned >2× expected tokens or wall-clock |
| `other` | Anything else worth naming |

Per-slice classifier prompt (used when log signal is ambiguous):

```
You are classifying a swarm slice failure for a night-shift retro.

Slice: #<num> — <title>
Outcome: <merged|blocked|deferred|auto-split>
Matrix failures (categories that failed in any attempt): <list>
Per-attempt logs: <inline>

Pick ONE failure mode from: thrashing, proxy-gaming, misalignment,
non-convergence, context-drift, runaway-resource, other.

Output JSON only:
  {"mode": "<one-of-above>", "narrative": "<one to two sentences>"}
```

## US-3: Identify action items

For each `failure` and each pattern of `matrix_fail_categories` repeated across slices, draft an action item:

```json
{
  "title": "...",
  "gap_class": "SYSTEM | PROJECT | UNCLEAR",
  "source_repo": "ronan-skills | factory | <project-name>",
  "severity": "high | med | low",
  "proof_ref": "PR#156 or issue#229",
  "created_issue": null
}
```

Classification heuristics:

- **SYSTEM** — the failure shape would recur in a different repo using the same skill / matrix. E.g. "the planner-worker matrix is missing a row for D1 migration collisions across parallel workers" → SYSTEM, `source_repo: ronan-skills`. "The factory reconciler missed an inflight slice race" → SYSTEM, `source_repo: factory`.
- **PROJECT** — the failure is repo-specific. E.g. "the dataforce onboarding flow has a router-shadowing bug" → PROJECT, `source_repo: dataforce`.
- **UNCLEAR** — surfaced once, no pattern yet; revisit on second occurrence.

`severity` is a rough triage hint:

| severity | When |
|---|---|
| `high` | Blocked a merge, recurred 3+ times, or surfaced in production |
| `med` | Recurred 2+ times, or blocked a single merge |
| `low` | One-off observation, worth noting but not urgent |

## US-4: Write the artefact pair

Compose the JSON per the schema in [[night-shift-retro-and-day-shift]] § "Artefact pair". Write to:

```
<repo>/.nightshift/retros/<YYYY-MM-DD>-<run-id>.json
<repo>/.nightshift/retros/<YYYY-MM-DD>-<run-id>.md
```

Markdown headers (each section mirrors a JSON block):

```markdown
# Night-shift retro — <YYYY-MM-DD> run <run-id>

## Run summary
- Dispatcher: <dispatcher>
- Mode: <mode>
- Repo: <repo>
- Branch: <branch>
- Started: <ISO8601>
- Ended: <ISO8601>
- Duration: <wall_clock_minutes>m
- JSON sibling: `.nightshift/retros/<YYYY-MM-DD>-<run-id>.json`

## Stats
| Metric | Value |
|---|---|
| Issues picked | <N> |
| PRs merged | <N> |
| PRs blocked | <N> |
| Issues deferred | <N> |
| Wall clock | <N>m |
| Approx tokens burned | <N> |

## Per-slice breakdown
| Issue | Title | Outcome | PR | Retries | Matrix fails | Wall clock |
|---|---|---|---|---|---|---|
| #234 | role picker | merged | #156 | 1 | e2e, logging | 22m |
...

## Failure modes hit
- #234 — thrashing — e2e + logging failed twice consecutively before the third attempt passed. Likely a missing logging contract row in the matrix.
...

## Action items
- [ ] **[SYSTEM][ronan-skills][high]** Add D1 migration-slot pre-assignment to planner-worker dispatch prompt (proof: PR#156)
- [ ] **[PROJECT][dataforce][med]** Onboarding router-shadowing: investigate `/onboarding/role` redirect cycle (proof: issue#229)
- [ ] **[UNCLEAR]** Worker for #240 spent 38m investigating Nango SDK before producing useful diff; revisit if pattern recurs

## SYSTEM gaps surfaced
- The verify-logging contract caught two silent catch blocks; matrix row 5 worked. No SYSTEM gap.
- The e2e matrix row caught zero failures in three slices that shipped routing changes; SYSTEM gap: the slicer's "e2e mandatory" block isn't reaching workers consistently. File against ronan-skills.

## Cross-repo issues opened
- ronan-skills#<N> — "[from-retro] Pre-assign Drizzle migration slots in planner-worker dispatch"
- dataforce#<N> — "[ready-for-human] Onboarding router-shadowing investigation"
```

## US-4b: Render the morning briefing HTML (when `retros.morning_briefing: true`)

Default `true`. The briefing is the "wake-up-to-coffee" artefact: a single self-contained HTML page that Skip (or Ronan) opens first thing to see what shipped, what's open, and what to do today. It's also the deep-link target for the Pushover + Telegram tail call (more useful than the raw markdown).

Write to:

```
<repo>/.nightshift/briefings/<YYYY-MM-DD>[-<run-id-suffix>].html
```

If a briefing already exists for the date (e.g. you ran morning + evening night-shifts the same day), suffix the filename with the run-id so they don't collide:

```
.nightshift/briefings/2026-05-19.html              # morning run
.nightshift/briefings/2026-05-19-evening.html      # evening run
.nightshift/briefings/2026-05-19-20260519T1729Z.html  # if run-ids needed for disambiguation
```

Section shape (every briefing has these in this order):

1. **Header strip**: sticky top, `night-shift briefing` brand, date / repo / run-id meta.
2. **Hero card**: one-sentence headline (`Good morning. <N> PRs shipped, <signal>, <signal>.`), one paragraph follow-up summarising the run's shape.
3. **Merged this run**: per-PR card with title, slice link, additions/deletions, squash-merged status.
4. **New slices filed**: backlog growth grouped by parent issue; each slice link shows `merged` / `ready-for-agent` / `deferred`.
5. **What to do this morning (in order)**: 4-7 numbered actions. ALWAYS includes deploy step if PRs landed without auto-deploy. Format: `<verb> <noun>: <specific command or link>`.
6. **Open follow-ups**: every `needs-human` issue filed by workers + any PR review awaiting author action.
7. **Deploy status**: pending / done / failed with the relevant command (`/ro:cf-ship` for Cloudflare, `/ro:fly-deploy` for Fly).
8. **Biggest surprise**: 1-3 sentences capturing the most-likely-to-bite-us learning of the night. Surfaces SYSTEM gaps for the action-items list.
9. **Run summary**: stats table (started, ended, duration, waves, workers, PRs, slices, follow-ups, dupes, side-quests, failure modes).
10. **Links**: nightsheet GH issue, completion-report HTML, retro markdown + JSON, this briefing's path.

Reuse the GitHub dark palette CSS from any prior briefing on the same repo (look for `.nightshift/briefings/*.html`) so visual identity stays consistent across runs. If no prior briefing exists, use the canonical CSS block documented at [[night-shift-briefing-template]] (or fall back to a minimal one-pane stylesheet).

Implementation hint: build the HTML via a Python heredoc or a small `briefing.py` helper that reads the retro JSON + `gh pr view` for each merged PR. Don't shell out to a templating engine; the briefing is a single self-contained page.

Path emitted to `.nightshift/last-briefing-url.txt` (file:// URL) so US-7 picks it up.

## US-5: Cross-repo routing (when `open_followup_issues: true`)

For each action item with `created_issue: null`:

```bash
case "$gap_class:$source_repo" in
  SYSTEM:ronan-skills)
    issue_num=$(gh issue create -R RonanCodes/ronan-skills \
      --title "[from-retro] $title" \
      --label "from-retro" \
      --label "source-repo:$current_repo" \
      --label "run-id:$run_id" \
      --body "$(retro_body_for $item)" \
      | grep -oE '[0-9]+$')
    ;;
  SYSTEM:factory)
    issue_num=$(gh issue create -R RonanCodes/factory \
      --title "[from-retro] $title" \
      --label "from-retro" \
      --label "source-repo:$current_repo" \
      --label "run-id:$run_id" \
      --body "$(retro_body_for $item)" \
      | grep -oE '[0-9]+$')
    ;;
  PROJECT:*)
    # Current repo only; ready-for-human (NOT swarm) — must be grilled first
    issue_num=$(gh issue create \
      --title "$title" \
      --label "ready-for-human" \
      --label "from-retro" \
      --body "$(retro_body_for $item)" \
      | grep -oE '[0-9]+$')
    ;;
  UNCLEAR:*)
    issue_num=""   # stays in retro markdown only
    ;;
esac
```

Body template for `retro_body_for`:

```markdown
## Source

Surfaced by `/ro:night-shift-retro` against `$current_repo` run `$run_id` (<ISO8601>).

Retro artefact: `<repo>/.nightshift/retros/<date>-<run-id>.md`

## Failure context

<narrative from the failure[] entry, or pattern summary if synthesised>

## Proof

<proof_ref — link to PR / issue / log excerpt>

## Severity

<severity>

---

This issue was filed automatically. If it does not represent real work, close with `wontfix` and leave a comment so the retro classifier can learn.
```

Update the JSON's `action_items[].created_issue` with the newly-minted issue number.

## US-6: Commit the artefact (when `commit_to_project: true`)

```bash
cd "$repo"
git add .nightshift/retros/<date>-<run-id>.{md,json}
git commit -m "📝 docs(retro): night-shift run $run_id ($N merged, $M blocked, $K followups)"
```

Use the repo's commitlint format. The dataforce repo uses emoji-conventional with the `📝 docs` prefix; ronan-skills + factory use the same. Skip the commit under `--no-commit` or `commit_to_project: false`.

## US-7: Update the dispatcher's tail-call notification

Deep-link target priority (most useful first): briefing HTML > retro markdown > completion-report HTML. If the briefing was rendered (US-4b), Pushover + Telegram point at it; otherwise fall back to the retro markdown.

If the dispatcher (night-shift / ralph / planner-worker / agentic-e2e-flow) has already fired Pushover + Telegram, the retro patches the message via `--update`:

```bash
url="file://$repo/.nightshift/briefings/$date.html"
[ -f .nightshift/last-briefing-url.txt ] && url=$(cat .nightshift/last-briefing-url.txt)
bash ~/Dev/ronan-skills/skills/pushover/scripts/notify.sh \
  --update \
  "$(echo "$dispatcher message" + retro summary line)" \
  --url "$url"
```

If the dispatcher has NOT yet fired the notifications, prepare the deep-link path so the dispatcher's tail call picks it up:

```bash
echo "$repo/.nightshift/briefings/$date.html" > .nightshift/last-briefing-url.txt   # preferred
echo "$repo/.nightshift/retros/$date-$run_id.md" > .nightshift/last-retro-url.txt   # fallback
```

Dispatchers read `last-briefing-url.txt` first, then `last-retro-url.txt`, and inject whichever exists into their Pushover + Telegram tail call. The Telegram script does not accept `--url`; embed the URL inline in the message body instead.

## US-8: Auto-skill-retro (when `auto_skill_retro: true`)

When the run touched a SKILL.md file (rare in autonomous runs, but possible when the swarm targets ronan-skills itself), invoke `/ro:skill-retro --since <run-start>` automatically after the retro is written.

Default `auto_skill_retro: false` keeps `/ro:skill-retro` as the manual consolidation gate — they have different shapes:

- `/ro:night-shift-retro` — run-level signals (what happened during ONE swarm run)
- `/ro:skill-retro` — skill-level evolution (which SKILL.md files need editing across many runs)

## Errors

| Condition | Message |
|---|---|
| No `.swarm/`, `.ralph/`, or recent merged PRs | "No run data found. Pass `--run-id <id>` or run from a repo that just finished a /ro:night-shift / /ro:ralph --afk / /ro:planner-worker --afk." |
| `.ronan-skills.json` missing | Initialise with the default `retros.*` block and continue. |
| `gh auth` failed AND `open_followup_issues: true` | "gh CLI not authed; skipping cross-repo issue creation. Action items captured in markdown only. Re-run with `gh auth refresh` to file follow-ups." |
| Repo mode `unset` | Run the [[repo-mode]] first-run prompt, persist, continue. |
| Two retros for the same `run_id` | "Retro already exists at `<path>`. Pass `--run-id <new-id>` or delete the existing file first." |

## Anti-patterns

1. **Filing every UNCLEAR action item.** They flood the wrong backlog. Hold them in the markdown until a second occurrence.
2. **Routing PROJECT items to `ready-for-agent` / `swarm`.** PROJECT issues need a human grill round; the `ready-for-human` label gates that.
3. **Skipping the retro because the run was small.** Even a 2-PR run captures token-burn-rate signal worth comparing across nights.
4. **Mixing `/ro:night-shift-retro` and `/ro:skill-retro` in one commit.** Different shapes, different cadence, different repos. Keep them apart.
5. **Auto-firing the retro on `--plan-only` runs.** Nothing happened; there's nothing to retro. The dispatcher should skip the invocation.

## See also

- [[close-the-loop-verification-matrix]] — the matrix the retro tracks failures against
- [[night-shift-retro-and-day-shift]] — the pattern note describing the async chain
- `/ro:day-shift` — the morning sibling that grills the backlog for the next run
- `/ro:skill-retro` — the manual SKILL.md consolidation gate (different shape)
- `/ro:night-shift` — the primary dispatcher; Phase 7 invokes this skill
- `/ro:planner-worker` — single-wave dispatcher; emits `failures[]` entries the retro reads
- `/ro:pushover` + `/ro:telegram` — notification deep-link recipients

## Provenance

- **2026-05-19** — created in response to the dataforce night-shift run that merged 11 PRs but shipped one broken (`/onboarding/role` redirect loop). Without a retro the SYSTEM gap (e2e mandatory in every slice body) would have surfaced one regression at a time. The retro turns the post-mortem into structured data: SYSTEM action items file against ronan-skills / factory; PROJECT action items file against the current repo with `ready-for-human`. Born alongside [[close-the-loop-verification-matrix]] + [[night-shift-retro-and-day-shift]].
- **2026-05-19 (evening)** — added US-4b: morning-briefing HTML rendered to `.nightshift/briefings/<date>.html` and made the Pushover + Telegram deep-link target. The `retros.morning_briefing: true` config flag had been dangling, no skill consumed it; this US wires it up. Surfaced during the evening night-shift run that merged 7 PRs and did not produce a briefing automatically. Also clarified that Telegram's notify script does not accept `--url`, so the briefing path is embedded inline in the message body.
