---
name: grill-with-docs
description: Grill-mode plus lazy documentation. Runs the grill-me interrogation and, as decisions are reached, writes them into CONTEXT.md (domain language) and docs/adr/000N-*.md (hard-to-reverse decisions) so a fresh agent can pick up cold without re-grilling the user. Triggers on "grill with docs", "/grill" in agent-native repos, "grill and document", "interview me and write it down", or when the user wants the grill output captured persistently rather than living in the chat transcript.
allowed-tools: Bash Read Glob Grep Write Edit
---

# Grill With Docs

Wrapper around [matt-pocock/skills/grill-me](https://www.aihero.dev/my-grill-me-skill-has-gone-viral) and `ubiquitous-language` that, as the interrogation proceeds, materialises two persistent artefacts:

- `CONTEXT.md` (or `CONTEXT-MAP.md` + per-context files for multi-bounded-context repos) — the domain language a future agent needs to reason inside this codebase. Built incrementally from terms that surface during grilling. Synthesises Pocock's `ubiquitous-language` skill output with the in-grill terms.
- `docs/adr/000N-<slug>.md` — one Architecture Decision Record per hard-to-reverse decision (database choice, auth provider, deployment substrate, framework, etc.). Format: Context / Decision / Consequences. Sequential N. Written only when a decision is irreversible enough to warrant a record.

The point: the grill transcript dies with the session. CONTEXT.md and ADRs survive into the next agent's context window. Write them lazily during the grill, not after.

## Bootstrap (idempotent)

Before grilling, ensure Matt's upstream skills are reachable:

```bash
test -e ~/.claude/skills/grill-me || npx -y skills@latest add mattpocock/skills/skills/productivity/grill-me -g
test -e ~/.claude/skills/ubiquitous-language || npx -y skills@latest add mattpocock/skills/skills/architecture/ubiquitous-language -g
```

No-op if both are already symlinked.

## How it runs

1. **Open with grill-me's interrogation.** One question at a time, always with a recommended answer and why. Walk the decision tree foundations-first. Same rules as the base `grill-me` skill.
2. **Listen for two signals** as answers come back:
   - **Domain term lands** (a noun or verb the user names with intention: "Pulse run", "reorder watch", "sandcastle", "lock graph", "trust gradient"). Append it to `CONTEXT.md` under the right section with a one-line definition, plus aliases-to-avoid if the user has been using competing words.
   - **Hard-to-reverse decision reached** (database engine, auth provider, deployment platform, framework, public API contract, naming of a load-bearing concept). Prompt: "this looks ADR-worthy — write `docs/adr/000N-<slug>.md`? y/n". On `y`, write it with sections: **Context**, **Decision**, **Consequences**, **Status: accepted**, **Date: YYYY-MM-DD**.
3. **Never write the destination PRD inside grill-me.** Hand that to `write-a-prd` after the grill closes. `grill-with-docs` writes only `CONTEXT.md` and ADRs — they are independent of any specific PRD and outlive it.
4. **Close with a printed manifest** of files written this session:

   ```
   Wrote during this grill:
   - CONTEXT.md (+4 terms: Pulse run, reorder watch, lock graph, trust gradient)
   - docs/adr/0007-substrate-cf-workers-not-fly.md
   - docs/adr/0008-sync-via-pr-not-shared-fs.md
   ```

## When to use vs base `grill-me`

| Use base `grill-me` | Use `grill-with-docs` |
| --- | --- |
| Quick design check in the chat, output is throwaway | Building a real repo; documentation needs to outlive the session |
| Repo has no `docs/adr/` and you don't want one | Repo is agent-native (Pocock pattern); next agent must pick up cold |
| You'll write the PRD yourself right after | You want the domain language and irreversible decisions captured separately from the PRD |

In agent-native repos following the [Pocock pattern](https://www.aihero.dev/) — single `ready-for-agent` label, PRDs as GH issues, slices as child issues — `/grill` should route to **this** skill by default. The base `grill-me` is the fallback for ad-hoc design conversations.

## CONTEXT.md template (initial scaffold if missing)

```md
# Context

A future agent reading this file alone should be able to pick up unfamiliar work in this repo without re-asking the same questions.

## Domain

| Term | Definition | Aliases to avoid |
| --- | --- | --- |

## System shape

(Top-level components and how they talk to each other. 5-10 bullets max.)

## Conventions

(Style choices that aren't captured in lint/format config — naming, error-handling stance, test-vs-runtime invariants.)
```

For multi-bounded-context repos: write `CONTEXT-MAP.md` at the root pointing at `contexts/<name>/CONTEXT.md` per bounded context. Trigger this layout when the grill surfaces two or more distinct domain languages (e.g. "scheduling terms" vs "billing terms") that don't share vocabulary.

## ADR template

```md
# ADR-000N: <slug>

- **Status**: accepted
- **Date**: YYYY-MM-DD

## Context

(What forces are at play. The grill question that triggered this ADR.)

## Decision

(The choice, stated as a single sentence.)

## Consequences

(What this commits us to. What we can no longer easily do. What we now have to do.)
```

## Don'ts

- Don't write `CONTEXT.md` or ADRs **before** the grill reaches the relevant decision — that defeats the lazy point. Write only when the user has confirmed the term or decision.
- Don't include the PRD content in CONTEXT.md. The PRD describes one feature; CONTEXT.md describes the repo.
- Don't ask "should I write an ADR?" on every reversible decision. The bar is: would changing this require a database migration, a vendor switch, or rewriting all the consumers? If not, skip the ADR.
- Don't number ADRs by guessing. List `docs/adr/*.md`, pick `max(N) + 1`. Create the directory if absent.
