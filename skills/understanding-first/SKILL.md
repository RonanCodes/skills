---
name: understanding-first
description: When generating wiki pages, READMEs, POC docs, integration write-ups, architecture notes, design docs, or any artefact whose purpose is for the user to *understand* a topic — not just record information. Apply BEFORE writing the artefact, then validate against the checklist before saving. The "outsource thinking, not understanding" principle.
category: communication
---

# Understanding-First

> Outsource thinking. Don't outsource understanding.

Generated docs must **teach the reader**, not just **record facts**. When a reader (you, a future agent, a teammate) is done with the page, they should know **why** the thing exists, **how** it works at a glance, and **where** to dig deeper. If they only learn what the page is *about*, the doc failed.

## When this applies

Auto-load when generating:

- Wiki pages (especially integration, concept, and architecture pages)
- READMEs and getting-started docs
- POC explainers
- Technical write-ups, design notes, ADRs (Architecture Decision Records)
- Onboarding / handover docs
- Any artefact whose value is the reader's understanding, not just the file's existence

Don't apply to:

- Pure-data files (CSVs, structured JSON dumps)
- Code (use `coding-principles` instead)
- Quick chat responses where context is already in scope

## The contract

Every doc covered by this skill must include the seven elements below, in this order where practical.

| # | Element | Why |
|---|---------|-----|
| 1 | **Plain-English explainer** (lead paragraph) | The "what is this and why does it exist" before any detail. Reader should be able to stop here and have the gist. |
| 2 | **Acronym handling** (inline-on-first-use + glossary if dense) | Every acronym expanded the first time it appears. No "of course you know what an ORM is." |
| 3 | **Mermaid diagram** of flow or structure | Diagrams compress 200 words of prose. One per page minimum for any flow or relationship. |
| 4 | **Concrete worked example** | One real scenario walked end-to-end with real values, not placeholders. Examples teach faster than abstractions. |
| 5 | **Citations** (sources of facts) | Every non-obvious claim cites where the fact came from: vendor docs URL + version, API spec endpoint, source file path, meeting date. |
| 6 | **Further reading** (links to learn more) | External links to vendor docs, blog posts, talks, related concept pages. Distinct from citations: citations are *where this fact came from*; further reading is *where to go to deepen understanding*. |
| 7 | **Open questions** (explicit section) | Anything not known goes in its own "Open" section with the question + who can answer it + how to chase it. Never bury uncertainty in prose. |

## Acronym handling — the small thing that matters

First use of any acronym, format:

```
SSR (Server-Side Rendering — pages rendered on the server, not in the browser)
RSC (React Server Components — server-rendered component model used in Next.js / TanStack Start)
ORM (Object-Relational Mapper — e.g. Prisma, Drizzle)
ADR (Architecture Decision Record)
MOC (Map of Content — an Obsidian convention for hub pages)
```

For docs with 4+ distinct acronyms, add a **Glossary** section at the top, ordered alphabetically, one line per acronym.

## Citations vs further reading

| | Citations | Further reading |
|---|---|---|
| Purpose | *Where this fact came from* | *Where the reader can deepen understanding* |
| Format | Inline links + `sources:` frontmatter | Footer section `## Further reading` |
| Required? | Yes, for every non-obvious claim | Yes, ≥3 links for any tech topic |
| Examples | Vendor docs URL + version, OpenAPI spec `POST /webhooks` v2.4, screenshot path `raw/<source-slug>/screen.png`, dated meeting note | Vendor developer docs, related blog post, conference talk recording, vendor's GitHub repo |

For any third-party technology mentioned (e.g. your auth provider, database, payments processor, file-storage vendor, message queue) include **at least one online further-reading link** so the reader can verify or extend.

## Reference exemplar

A "gold-standard" understanding-first doc lets a stranger become productive in one sitting. They leave knowing **why** the system exists, **how** the major pieces fit, and **where** to go next — without follow-up questions. Karpathy's tutorial-style READMEs (e.g. [nanoGPT](https://github.com/karpathy/nanoGPT)) are a public example of this pattern. Use any similarly-written OSS doc as a model.

## Counter-exemplar

A page titled "Webhooks" containing:

```markdown
We use a payments provider for checkout. There are 2 webhook events
we care about. The signing secret is stored somewhere. See the wiki.
```

What's wrong:

- No **why** (why this provider? why those 2 events specifically?)
- No **how** (how is the signing secret validated step-by-step?)
- No **diagram**
- "Somewhere" is not a citation — it's hand-waving
- No **acronyms expanded** (does the reader know what a signing secret *is*, or how it differs from an API key?)
- No **worked example** with a real event payload
- No **open-questions section** (the "somewhere" should be a flagged open question, not buried in prose)
- No **further reading** for the reader who wants to learn webhook security properly

## Pre-publish checklist

Before saving any doc covered by this skill, verify:

- [ ] Lead paragraph teaches the **why** + **how at a glance**
- [ ] Every acronym expanded on first use (and glossary if 4+)
- [ ] At least one mermaid diagram
- [ ] At least one concrete worked example
- [ ] Every fact has a citation (inline + `sources:` frontmatter)
- [ ] "Further reading" section with ≥3 online links for tech topics
- [ ] "Open questions" section if anything is unknown or pending
- [ ] No jargon walls, no data dumps, no "see the wiki" hand-waves

If any box is unticked, the doc is not understanding-first. Revise before saving.

## Diagram theming

Default to a consistent palette across a project for visual consistency. A balanced default:

- Amber `#e0af40` for user / source nodes
- Cyan `#5bbcd6` for engine / skill / system nodes
- Green `#7dcea0` for output / result nodes

Adjust per project's brand palette if one exists.

## Frontmatter that supports this skill

Pages produced under this contract should carry frontmatter that makes citations and further reading machine-readable:

```yaml
---
title: <human-readable title>
page-type: integration | concept | architecture | adr | onboarding | poc-explainer
sources:
  - "docs-cms:<space>:<page-id>@<version>"
  - "openapi:<api-name>:<endpoint>"
  - "raw:<source-relative-path>"
  - "meeting:<date>:<topic>"
further-reading:
  - url: https://...
    title: "..."
    why: "Vendor docs for the API used in this integration"
open-questions:
  - question: "Which endpoint owns this data — A or B?"
    owner: "<person to chase>"
    raised: <YYYY-MM-DD>
---
```

Skills that surface "everything with open questions" or "everything citing docs-cms page X" rely on this shape — keep it consistent.
