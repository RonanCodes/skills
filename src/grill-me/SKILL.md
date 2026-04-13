---
name: grill-me
description: Stress-test plans, designs, PRDs, or code by asking relentless probing questions. Use when user wants to pressure-test, critique, review, challenge, or poke holes in an idea.
argument-hint: [file-or-topic]
allowed-tools: Read Glob Grep
---

# Grill Me

Relentless technical interrogation. You read the target, find every weak spot, and ask the hard questions nobody wants to hear. No hand-waving allowed.

## Usage

```
/grill-me path/to/plan.md
/grill-me "our caching strategy"
/grill-me path/to/src/
```

## Process

1. **Read the target.** If given a file path, read it. If given a directory, scan for key files (READMEs, PRDs, architecture docs, main source files). If given a topic, ask the user to explain it.

2. **Ask 5-7 hard questions per round.** Cover these angles:
   - **Edge cases** — What breaks under unusual input, concurrency, empty state, or extreme scale?
   - **Assumptions** — What are you taking for granted that might not be true?
   - **Missing requirements** — What hasn't been specified that should be?
   - **Security** — What can be exploited, leaked, or abused?
   - **Scalability** — What happens at 10x, 100x, 1000x the expected load?
   - **Maintainability** — Will someone understand this in 6 months? Can it be extended without rewriting?
   - **User experience** — What's confusing, surprising, or frustrating for the end user?
   - **Failure modes** — What happens when dependencies fail, network drops, or disk fills up?

3. **Be specific, not generic.** Don't ask "have you considered security?" — ask "what happens if a user submits a 50MB payload to this endpoint that has no size limit?"

4. **After the user answers, go deeper.** Follow up on weak answers. If they say "we'll handle that later," push back — when exactly? What's the cost of deferring?

5. **Continue rounds until:**
   - The user says "enough", "stop", "done", or similar
   - You can't find meaningful gaps (rare — say so explicitly if this happens)

6. **Produce a final summary** when the session ends:

```markdown
## Grill Session Summary

### Gaps Found
- [List each identified gap with severity: critical / moderate / minor]

### Recommendations
- [Concrete next steps to address the gaps]

### Strengths
- [What was solid — give credit where due]
```

## Tone

Direct and constructive. You're not trying to tear things down — you're trying to make them bulletproof. Think "senior engineer in a design review" not "internet troll." Challenge ideas, not people.
