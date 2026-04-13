---
name: post-mortem
description: Document a resolved bug or incident as a structured post-mortem. Captures root cause, what was tried, what fixed it, and lessons learned — committed locally for future reference.
argument-hint: [short description of the issue]
---

# Post-Mortem

After resolving a tricky bug or incident, document what happened so you never debug the same thing twice. Creates a structured markdown file committed to the repo.

## Usage

```
/post-mortem "stale closure in useEffect causing infinite re-renders"
/post-mortem "CI failing on arm64 — missing native dependency"
/post-mortem
```

If no argument is given, ask the user to describe the issue that was just resolved.

## When to Use

- After `/debug-escape` finds the root cause and the fix is applied
- After any bug that took more than 15 minutes to solve
- After an incident, outage, or production issue is resolved
- When you discover a non-obvious gotcha that someone else will hit

## Process

### 1. Gather Context

Collect information from the current session:
- What was the symptom? (exact error message, unexpected behavior)
- What was tried? (list failed attempts — these are valuable)
- What was the root cause?
- What fixed it?
- How long did it take to find?

Check git history for supporting context:
- `git log --oneline -10` — recent commits related to the fix
- `git diff` — what changed in the fix

### 2. Write the Post-Mortem

Create the file at `.post-mortems/<date>-<slug>.md` where:
- `<date>` is YYYY-MM-DD
- `<slug>` is a kebab-case summary (e.g. `stale-closure-useeffect`, `ci-arm64-native-dep`)

Use this template:

```markdown
# <Title>

**Date:** <YYYY-MM-DD>
**Time to resolve:** <approximate>
**Severity:** <low | medium | high | critical>
**Area:** <file path, module, or system area>
**Tags:** `bug/introduced/<slug>` → `bug/fixed/<slug>`

## Symptom

<What was observed — exact error messages, unexpected behavior, how it manifested>

## Root Cause

<What was actually wrong and why — be specific>

## What We Tried

1. <First attempt> — <why it didn't work>
2. <Second attempt> — <why it didn't work>
3. ...

## What Fixed It

<The actual fix — reference the commit if already committed>

```diff
<include the key diff if short enough>
```

## Lessons Learned

- <Non-obvious insight that would help someone hitting this in future>
- <What to check first next time>

## Related

- <Links to relevant docs, GitHub issues, or Stack Overflow answers found during debugging>
```

### 3. Tag the Fix

Tag the fix commit so it's easy to find via `git tag -l "bug/*"`:

```bash
git tag bug/fixed/<slug> <fix-commit-hash>
```

If `/debug-escape` already tagged the introducing commit as `bug/introduced/<slug>`, reference both in the post-mortem. If the introducing commit wasn't tagged yet and you know which commit introduced the bug, tag it now:

```bash
git tag bug/introduced/<slug> <introducing-commit-hash>
```

The tag pair tells the full story: `git log bug/introduced/<slug>..bug/fixed/<slug>` shows everything between cause and cure.

### 4. Update .gitignore if Needed

Check if `.post-mortems/` is gitignored. It should NOT be — these files are meant to be committed and shared with the team.

### 5. Commit

Stage and commit the post-mortem:

```bash
git add .post-mortems/<date>-<slug>.md
git commit -m "📝 docs: post-mortem — <short description>"
```

## Rules

1. Write for your future self — assume you've forgotten everything about this bug
2. Include exact error messages, not paraphrases
3. Document failed attempts — knowing what doesn't work is as valuable as the fix
4. Keep it concise — a post-mortem is a reference doc, not a narrative
5. If the fix commit is already made, reference its hash
6. Never skip the "Lessons Learned" section — that's the whole point
7. Always tag the fix commit with `bug/fixed/<slug>` — tag the introducing commit too if known
