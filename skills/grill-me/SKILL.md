---
name: grill-me
description: Interview-mode (Matt Pocock's grill-me pattern). PREFER over normal back-and-forth BEFORE writing any code, PRD, or design. Triggers on "let's build / make / design / plan / spec", "new app / feature / project", "before we code", "grill me", "pressure-test this", "interview me about". Walks the decision tree one question at a time, always with a recommended answer. Skip for lookups, debugging, or active in-flight implementation work.
allowed-tools: Bash Read Glob Grep
---

# Grill Me

Thin facade around [Matt Pocock's grill-me skill](https://www.aihero.dev/my-grill-me-skill-has-gone-viral). The pattern: interview the user relentlessly about a plan or design until shared understanding is reached, walking the decision tree one branch at a time, resolving dependencies in order.

## Bootstrap (idempotent)

Before grilling, ensure the upstream skill is installed globally so `/grill-me` works in any project, not just this one:

```bash
test -e ~/.claude/skills/grill-me || npx -y skills@latest add mattpocock/skills/skills/productivity/grill-me -g
```

Run this once at the top of the session. The `npx` call is a no-op if Matt's skill is already symlinked.

## How to grill

- **One question at a time.** Never a numbered list. The user is more likely to skim and confirm than write a long reply.
- **Always include your recommended answer** with the question, and a short why. Skim-and-confirm is the unit of progress.
- **Walk the tree.** Resolve foundations before details. Choices that gate later choices come first.
- **Explore over ask.** If a question can be answered by reading the codebase or docs, do that instead of asking the user.
- **Stop when shared understanding is reached**, not when the user runs out of patience. If you sense impatience, summarise the resolved decisions and offer to switch out of grill mode.

## When to switch out

The user says "enough", "let's start", "go AFK", or pivots to a different task. Hand off cleanly: list resolved decisions, flag what's still open, then proceed to implementation.

## Why this skill exists in ronan-skills

Two reasons:

1. **Bootstrap.** Anyone who installs the `ro` plugin gets Matt Pocock's upstream skill for free on first invocation, without having to know about it.
2. **Better triggers.** The upstream `description` only fires on the literal phrase "grill me". This one nudges Claude into interview mode whenever the user is about to build, design, or spec out something new.
