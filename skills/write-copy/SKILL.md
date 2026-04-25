---
name: write-copy
description: Style rules for writing human-sounding copy. Apply whenever producing user-facing text (READMEs, landing pages, docs, marketing, tweets, UI microcopy, PR descriptions, release notes). The core goal is to avoid the tells that make writing look AI-generated.
category: writing
argument-hint: (reference skill; loaded automatically when writing copy)
---

# Write Copy

Reference skill Claude should load whenever writing copy a human will read. Purpose: strip out the tells that make writing look AI-generated.

## The rules

### 1. No em-dashes

Do not use `—` (U+2014) or `–` (U+2013, en-dash). Em-dashes are the single strongest AI tell in 2025 prose because LLMs overuse them as a catch-all connector.

**Replace with:**

| Original intent | Use instead |
|---|---|
| Aside / parenthetical | Comma, or parentheses: `(like this)` |
| Sharp break before a clause | Full stop. Start a new sentence. |
| Definition / expansion | Colon: `Term: explanation` |
| Range | `to` or `through` (`8:30 to 18:00`, not `8:30–18:00`) |
| List item label | Colon: `**Label**: description` |

**Bad:** `TanStack Start — full-stack React with file-based server routes.`
**Good:** `TanStack Start: full-stack React with file-based server routes.`

**Bad:** `It worked fine — until the database grew.`
**Good:** `It worked fine. Then the database grew.`

Use `-` (hyphen, U+002D) only for compound words (`runtime-injected`, `sub-10ms`), never as punctuation.

### 2. No rhetorical-reversal filler

Phrases like `"it's not just X — it's Y"`, `"not only A, but also B"`, and `"more than just a tool, it's a..."` are AI stock phrases. Cut them. State the Y directly.

### 3. Drop the AI vocabulary

These words are statistically over-represented in LLM output. Swap or delete:

- `delve into` → `look at`, `dig into`, or just `look`
- `leverage` → `use`
- `robust` → specific quality (`fast`, `battle-tested`, `covers edge cases`)
- `seamless` / `seamlessly` → just say what happens
- `intricate` / `nuanced` → `complicated`, `detailed`, or cut
- `navigate` (metaphorical) → `handle`, `work through`
- `in the realm of` → `in`
- `tapestry`, `landscape`, `ecosystem` (as filler) → name the specific thing
- `crucial`, `essential`, `vital` → usually cuttable; if not, say why
- `testament to` → cut
- `game-changer`, `paradigm shift` → cut
- `whether you're a X or a Y` → name one audience

### 4. No tricolons unless earned

Don't pad sentences with rule-of-three lists when two items or one would do. `"It's fast, reliable, and scalable"` is a tell. `"It's fast"` plus a concrete reason is better.

### 5. Active voice, concrete subjects

- **Bad:** `Observability is enhanced by the runtime-injection pattern.`
- **Good:** `Runtime injection means you can rotate keys without rebuilding.`

### 6. No hedging stacks

One hedge is fine, two is bureaucratic: `"may potentially possibly"`, `"somewhat relatively"`. Pick one or drop.

### 7. Cut throat-clearing

Openers to delete:
- `It's worth noting that...`
- `Broadly speaking...`
- `At the end of the day...`
- `In today's fast-paced world...`
- `When it comes to X...`
- `Ultimately...` (usually)

### 8. Specific > abstract

- **Bad:** `leverages modern tooling`
- **Good:** `uses Vite 7 + TanStack Start`

- **Bad:** `improves performance significantly`
- **Good:** `cuts p95 from 340ms to 95ms`

### 9. Earn exclamation marks and emoji

One emoji per doc, maybe. No exclamation marks unless the context genuinely warrants one. LLMs over-produce both.

### 10. Read it out loud

If a sentence sounds like a CEO presenting at a conference, rewrite it as a sentence you'd say to a colleague.

## Self-check before shipping

Search the draft for each of these. Every hit is a candidate for deletion or replacement.

```
— – · delve leverage robust seamless tapestry landscape
crucial essential vital testament game-changer paradigm
"not only" "it's not just" "more than just" "in today's"
"at the end of the day" "when it comes to"
```

A quick command:

```bash
rg -n '—|–|\bdelve\b|\bleverage\b|\brobust\b|\bseamless\b|\btapestry\b|\blandscape\b|\bnot only\b|\bit'\''s not just\b' <file>
```

## Voice exemplars

Models to emulate, not boilerplate to copy verbatim.

### Becca's launch voice: Connections Helper on LinkedIn

> Are you ever stumped by Connections because you don't know a word's meaning? Then check out this app I made called Connections Helper: https://lnkd.in/eTjTe4Ev
>
> You can:
> • Check the definitions of all of today's words from a range of dictionaries (Merriam-Webster, Urban Dictionary, etc)
> • Get clues to help you solve
> • Go back to any date for more definitions and clues
>
> Give it a go the next time you play Connections!
>
> #NYTConnections #Connections #ConnectionsHelper

Why it works:

- **Question hook in the first 7 words.** "Are you ever stumped by Connections" pulls in anyone who's played the puzzle. The hook *names a feeling*, not a feature.
- **Specific pain, not generic.** "Don't know a word's meaning" beats "struggling with the puzzle". The concrete failure mode is more recognisable than the abstract one.
- **"This app I made"** is the framing. Personal author, not corporate-voice. Reads like a friend recommending, not a brand pitching.
- **Bullets with concrete examples.** "(Merriam-Webster, Urban Dictionary, etc)" beats "multiple dictionaries". Naming the brands does the credibility work for free.
- **Casual imperative CTA.** "Give it a go the next time you play" reads like a friend. Compare the AI-tell version: "Try Connections Helper today and start solving smarter!". Exclamation, "today", "smarter" all signal marketer-voice.
- **Hashtags belong on LinkedIn, not X.** LinkedIn search uses them; X readers parse them as spam. Strip when porting.

The template, abstracted:

```
[question hook naming the pain in the first 7 words]
[soft transition to "this thing I made"]

You can:
• [value prop 1, with a concrete example]
• [value prop 2, with a concrete example]
• [value prop 3, with a concrete example]

[casual imperative CTA]

[hashtags, LinkedIn only]
```

Use for `@ronancodes` build-in-public launches and any "here's my new app" post. Skip the question hook on the second-tier platforms if it doesn't translate (Bluesky tends to want a flatter opener).

## What this skill does NOT cover

- Technical accuracy (that's on you)
- Tone for specific platforms (LinkedIn vs. X vs. docs; the voice changes, the rules above hold)
- Code comments (rules are laxer there; see `coding-principles`)
- PRDs (see `write-a-prd`, which governs structure; this skill governs voice)

## When to load

Load this skill at the start of any task that involves writing copy a human will read: README, landing page, marketing blurb, tweet, LinkedIn post, release notes, changelog entry, docs page, UI microcopy, email, PR description, commit message body, blog post. If Claude is only writing code, this skill is not needed.
