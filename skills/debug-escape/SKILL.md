---
name: debug-escape
description: Break out of debugging loops by stepping back and researching. Use when stuck, going in circles, hitting the same error repeatedly, or after multiple failed fix attempts.
category: development
argument-hint: [error-message-or-description]
allowed-tools: Bash(*) Read Write Edit Glob Grep WebSearch WebFetch
---

# Debug Escape

When you've tried the same thing three times and it still doesn't work, stop guessing and start researching. This skill provides a systematic escape from debugging loops.

## Usage

```
/debug-escape "TypeError: Cannot read properties of undefined"
/debug-escape "tests pass locally but fail in CI"
/debug-escape
```

If no argument is given, ask the user to describe what's failing and what they've already tried.

## Escape Strategies

Work through these in order. Stop as soon as you find the answer.

### 1. Look Back — Git History

- `git log --oneline -20` — what changed recently?
- `git diff HEAD~5` — compare with a known-working state
- `git stash` current changes, run tests — did the problem exist before?
- If it worked before, `git bisect` or binary search the commit that broke it
- When you find the breaking commit, tag it for future reference:
  ```bash
  git tag bug/introduced/<slug> <commit-hash>
  ```
  This makes it trivial to find later: `git tag -l "bug/*"` lists all tagged bugs

### 2. Look Up — Documentation

- Identify the exact library, API, or tool that's failing
- Check if Context7 MCP is available (`mcp__context7__resolve-library-id` and `mcp__context7__get-library-docs`) — if so, use it to pull current docs
- Otherwise, read local docs: node_modules READMEs, installed package docs, man pages
- Check CHANGELOG or release notes — is this a breaking change between versions?
- Read the actual source of the failing dependency if needed

### 3. Look Around — Local Examples

- Search the codebase for similar patterns: how is this API used elsewhere?
- Check test files — they often show expected behavior and edge cases
- Look in `.reference/` repos for how other projects solve the same problem
- Check if there's a working example in the project's docs or examples/

### 4. Look Out — Web Research

- WebSearch the exact error message in quotes + library name + version
- Search GitHub Issues for the library — someone else likely hit this
- Check Stack Overflow for the specific error
- Look for migration guides if a version upgrade caused the issue

### 5. Divide and Conquer — Binary Search the Bug

Instead of tweaking small things, make big changes to find the boundary:
- Revert to a known-good state (stash, checkout, or comment out large sections)
- Confirm it works in the good state
- Restore half the changes — does it still work?
- If yes: the bug is in the other half. Restore that half instead
- If no: the bug is in this half. Split it again
- Keep bisecting until the exact breaking change is isolated
- This is faster than tweaking one thing at a time — 10 changes bisect in 4 steps, not 10

### 6. Step Back — Rethink

- Is the approach fundamentally wrong? Are we fighting the framework?
- Is there a simpler way to achieve the same goal?
- Write a minimal reproduction — strip away everything until the bug is isolated
- Check assumptions: is the version correct? Is the config actually loaded? Is the env var set?

## Output: Debug Report

After researching, produce a structured report:

```markdown
## Debug Escape Report

### Problem
[What's failing — exact error, reproduction steps]

### Attempts So Far
1. Tried X — failed because Y
2. Tried Z — same error

### Research Findings
- Docs say: [relevant finding]
- GitHub Issue: [link or summary]
- Git history: last working at commit [hash]
- Working example found in: [file or repo]

### Root Cause
[What's actually going wrong and why]

### Recommended Fix
[Specific, actionable fix based on research — not another guess]
```

## After the Fix

Once the bug is resolved, run `/post-mortem` to document what happened. Tricky bugs deserve a write-up — your future self will thank you.

## Rules

1. Do NOT retry the same approach that already failed
2. Research before guessing — reading docs for 2 minutes beats 20 minutes of trial and error
3. If Context7 MCP is available, prefer it over web search for library docs
4. Always check the version — "works in v2, broken in v3" is the most common root cause
5. If you still can't solve it after all strategies, say so clearly and suggest escalation paths
