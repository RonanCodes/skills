---
name: worktree
description: Coordinate multiple agents on one repo via a worktree-lock pool, so two agents never clobber each other's working tree. Acquire the first free slot (main, then beta/gamma… worktrees, created on demand), work there on your own branch, release when you've pushed. Use before modifying any repo that might be in use by another agent (factory, dataforce, etc.), or whenever you're told a repo is being worked on. Backed by `ro worktree`.
category: development
argument-hint: [acquire | release [slot] | status | reap]
allowed-tools: Bash(ro *) Bash(git *) Bash(jq *) Read
---

# worktree — don't clobber another agent's working tree

Multiple agents work the local factory at once. Two agents in the **same**
working tree corrupt each other's edits. The fix: a per-repo lock pool of
worktrees. You take a free slot, work there, hand it back when you've pushed.

## The protocol

```bash
# 1. Before touching a repo that might be busy, take a slot:
path="$(ro worktree acquire)"      # prints the path; stderr says which slot
cd "$path"

# 2. Do your work on your own branch (never main):
git checkout -b feat/whatever
# … edit, commit, run the local gate, push, open PR, squash-merge …

# 3. ALWAYS release when you've pushed and you're done:
ro worktree release
```

`acquire` locks the first free slot: **main** (the primary checkout) if free,
else an existing Greek worktree (`<repo>-beta`, `-gamma`, …), else it creates the
next Greek one off `origin/main`. `release` (run from inside the slot, or pass the
slot name) frees it and marks `pushed: true`.

**Releasing is load-bearing.** If you don't release, the slot stays busy and the
pool fills up. The only safety net is TTL reaping (`RO_WT_TTL`, default 6h) via
`ro worktree reap` — don't rely on it.

## State

- Lock file: `<main-checkout>/.ro/worktree-locks.json` (gitignored; `ro` adds
  `.ro/` to `.gitignore` automatically).
- Label yourself with `RO_AGENT=<name>` so `ro worktree status` shows who holds what.
- `ro worktree status` prints the whole pool; `ro worktree reap` frees stale slots.

## When to use

- Told "X is being worked on" → acquire a slot instead of editing the primary tree.
- Any unattended/parallel run (`/ro:planner-worker`, `/ro:night-shift`, `/ro:swarm`)
  touching a shared repo.
- Pairs with /ro:ship (do the work in the acquired slot, ship from there, then release).
