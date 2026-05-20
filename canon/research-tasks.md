# Canon: Research tasks

Some backlog items are **research / investigation**, not code. Their output is documentation: a market teardown, a pedagogy survey, an architecture spike, a competitor analysis. The local factory (and the remote factory) need a first-class way to run these so the close-the-loop is *"a solid, discoverable, bidirectionally-linked doc landed in the repo AND the LLM wiki"* instead of *"tests pass"*.

This canon defines the `kind:research` label, the `docs/research/` folder convention, the research close-the-loop matrix, and the research-worker dispatch prompt. It is the authoritative spec; the orchestrator skills (`night-shift`, `planner-worker`, `ralph`, `matt-pocock-coding-workflow`) point here rather than re-deriving.

## The label

`kind:research` (colour `5319E7`, deep violet) — a research / investigation task. Sits in the **kind** axis alongside `kind:prd`, `kind:slice`, `kind:incident`, `kind:chore` (exactly one kind per issue, per [[canon:labels]]).

A `kind:research` issue:

- Has acceptance criteria phrased as **questions to answer + a doc to produce**, not code to write.
- Goes through the same lifecycle labels (`needs-grilling` → `ready-for-agent` → `in-progress` → closed) as any other issue.
- Can be a child of a `kind:prd` parent (`## Parent\n\n#<N>`) when the research feeds a specific feature, or standalone when it's exploratory.
- Is picked up by orchestrators with the query `--label kind:research --label ready-for-agent` (mirrors the `kind:slice` pickup but routes to the research-worker prompt below).

## The folder convention — `docs/research/`

Every repo that runs research tasks grows a `docs/research/` tree:

```
docs/research/
  README.md                      # INDEX — the discoverable home. Table of every
                                 # research doc: title, status, linked issue(s),
                                 # wiki page, last-updated. Links to each doc.
  index.html                     # optional rendered index (see "Discoverability")
  <topic-slug>/
    README.md                    # the research doc itself (the canonical artefact)
    <child-topic>.md             # child docs when the topic decomposes
    sources.md                   # raw source list / link dump (optional)
    assets/                      # screenshots, diagrams (optional)
```

Rules:

1. **One folder per research issue**, slug derived from the issue title.
2. **`docs/research/README.md` is the index** and MUST be updated by every research worker to add a row for its new doc. The index is the "easy to find these docs later" surface the system promises.
3. **Child docs live under the topic folder** and are linked from that topic's `README.md`. A parent research doc can spawn child docs (e.g. "Duolingo teardown" → child docs for "gamification", "lesson structure", "A/B-tested mechanics").
4. **`docs/research/` is committed and tracked** (it is durable knowledge, like `.ralph/patterns.md`). Never gitignored.

## Bidirectional issue ↔ doc linking (load-bearing)

The whole point is that an issue and its doc point at each other, so you can navigate either direction and so a closed issue stays self-explanatory.

**Doc → issue** (front-matter at the top of `docs/research/<slug>/README.md`):

```markdown
---
title: <human title>
issue: https://github.com/<owner>/<repo>/issues/<N>
parent_doc: ../README.md          # or a parent topic doc, when this is a child
child_docs:                       # when decomposed
  - ./gamification.md
  - ./lesson-structure.md
wiki: llm-wiki-<vault>/<page-slug>
status: draft                     # flips to "merged" when the PR lands on main (locked)
sources: ./sources.md
last_updated: <YYYY-MM-DD>
---
```

**Issue → doc** (a section appended to the issue body, plus the close-with-summary comment):

```markdown
## Research output

- Repo doc: `docs/research/<slug>/README.md`
- Wiki page: `llm-wiki-<vault>/<page-slug>`
- Child docs: <list, or "none">
```

**Dependent-issues visibility on close:** when the research issue is closed via `Closes #N` in the doc PR, the doc's `status` flips to `merged` (locked = canonical). Any child research issues reference the parent via `## Parent\n\n#<N>`, so GitHub shows the dependency tree on the closed parent. The merged doc on `main` is the source of truth; the wiki copy is the cross-project-discoverable mirror.

## The research close-the-loop matrix

Replaces the test-based `### Close-the-loop verification matrix` for `kind:research` issues. A research worker's DoD:

- [ ] **Research done:** the questions in the issue ACs are each answered with cited sources (no hand-waving; every claim has a link).
- [ ] **Doc written:** `docs/research/<slug>/README.md` exists with the front-matter above, a findings section, a recommendations section, and a sources section.
- [ ] **Child docs:** if the topic decomposed, child docs exist under the topic folder and are linked from the parent doc's `child_docs` + body.
- [ ] **Index updated:** `docs/research/README.md` has a row for the new doc.
- [ ] **Wiki ingest:** the doc is ingested into the designated LLM wiki vault via `/ro:wiki` (or the wiki repo's ingest skill). The wiki page links back to the repo doc + the issue.
- [ ] **Bidirectional links verified:** doc front-matter links the issue; issue body links the doc; both resolve.
- [ ] **Issue summary comment:** a close-with-summary comment posted (Findings / Key sources / Recommendations / Follow-ups / Wiki link) BEFORE merge.
- [ ] **Static gate:** repo CI is green. Research PRs touch only `docs/**` (markdown), so the gate is just "lint/build/typecheck unaffected" — there are NO unit/integration/e2e tests for a research doc, and the orchestrator MUST NOT block on missing tests.
- [ ] **Lock on merge:** when the PR merges to `main`, `status` flips `draft` → `merged`. The merged doc is canonical.

The `swarm.missing_test_acs` gate (which refuses to dispatch code slices missing a test matrix) is BYPASSED for `kind:research` — a research issue legitimately has no test matrix. Orchestrators detect `kind:research` and skip the test-AC gate, applying this matrix instead.

## Research-worker dispatch prompt (the variant)

Where a code worker implements + tests + opens a code PR, a research worker investigates + documents + opens a docs PR. The dispatch prompt:

```
You are a RESEARCH WORKER for the <repo> factory. Your slice is a kind:research
issue. Output is documentation, NOT code. There are no tests; the close-the-loop
is a discoverable, bidirectionally-linked doc in the repo AND the LLM wiki.

You are in an isolated git worktree off main. Confirm pwd is NOT the main checkout.

1. Read the issue:  gh issue view <N>
2. Take the lifecycle label:  gh issue edit <N> --add-label in-progress --remove-label ready-for-agent
3. DEEP RESEARCH. Use WebSearch + WebFetch (and /ro:perplexity-research if available)
   to gather primary + secondary sources. Read actual articles, docs, papers — do
   not synthesise from memory. Aim for 8-15 distinct sources. Capture URLs.
4. Write docs/research/<slug>/README.md with the canonical front-matter (issue link,
   wiki target, status: draft, sources), a Findings section (every claim cited), a
   Recommendations section (what THIS project should do), and a Sources section.
   Decompose into child docs under the topic folder if the topic is large.
5. Update docs/research/README.md (the index) with a row for the new doc.
6. Ingest into the LLM wiki: <vault> via the wiki ingest path (see the issue's
   "Wiki target" line). The wiki page links back to the repo doc + the issue.
7. Append the "## Research output" section to the issue body (bidirectional link).
8. Commit (emoji-conventional, weekday-hours rule), push the worktree branch, open a
   PR with `Closes #<N>` + a 1-paragraph summary. CI gate is lint/build only.
9. Post the close-with-summary comment on the issue BEFORE merging:
   Findings / Key sources / Recommendations / Follow-ups / Wiki link.
10. Wait for CI green, then squash-merge via the repo's merge convention.

Failure protocol: if you cannot gather credible sources or the scope is unclear,
exit "stuck" with a one-line cause; leave the issue in-progress for human triage.
```

## Orchestrator integration

Each local-factory skill detects `kind:research` and routes to the research-worker prompt + research close-the-loop matrix instead of the code path:

- **`night-shift`** — the ranked-queue probe includes `kind:research` issues; a wave can mix code slices and research issues (research issues never conflict on file-areas since they only touch `docs/research/`, so they're always `parallel-eligible`).
- **`planner-worker`** — US-2a test-AC gate is skipped for `kind:research`; the worker dispatch picks the research prompt; the merger checks the research matrix (doc exists + index updated + wiki ingested + bidirectional links) instead of tests.
- **`ralph`** — same routing in the serial loop.
- **`matt-pocock-coding-workflow`** — the grill/plan/slice phases can emit `kind:research` issues for spikes; the loop phase routes them to research workers.

## Remote factory (Factory app) compatibility

The Factory app (`~/Dev/ai-projects/factory`, deployed) runs equivalent loops as a cloud service. It must stay compatible: same `kind:research` label, same `docs/research/` convention, same bidirectional-link contract, same "no tests, doc is the close-the-loop" rule. The factory's worker-runtime needs a research-worker mode mirroring the prompt above. Tracked as factory issues; the canon here is the shared contract both factories implement.

## Discoverability (index files)

The promise is "easy to find these docs later". Three layers:

1. **`docs/research/README.md`** — the markdown index, always current, one row per doc.
2. **`docs/research/index.html`** (optional) — a rendered, browsable index (same data, clickable in a browser without a markdown viewer). Generated from the markdown index; regenerate when the index changes.
3. **The LLM wiki vault** — the cross-project home. Wiki pages link back to repo docs + issues, so research done in lekkertaal is discoverable next to research done in dataforce.

## See also

- [[canon:labels]] — the label system `kind:research` slots into
- [[canon:d1-migrations]] — sibling canon
- `/ro:wiki` — the wiki ingest skill research workers call to close the loop
- `/ro:perplexity-research` — deep web research helper
- `/ro:night-shift`, `/ro:planner-worker`, `/ro:ralph`, `/ro:matt-pocock-coding-workflow` — orchestrators that route `kind:research`

## Provenance

- **2026-05-20** — created when the lekkertaal app needed deep research on language-learning pedagogy (flashcards, SRS, Duolingo/Babbel teardowns, evidence-based methods) + branding research, run as an AFK swarm. The research had no tests, so the close-the-loop had to be redefined as documentation. Generalised into the factory system (local + remote) the same night so dataforce / factory / any repo can run research tasks with the same contract.
