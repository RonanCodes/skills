---
name: swarm
description: Alias for /ro:planner-worker. Multi-agent coding swarm — planner + worker + merger over git worktrees on the Max plan. When the user types /ro:swarm, /swarm, "kick off the swarm", "run the swarm", "swarm coding", or anything matching "swarm + code/PR/PRD", redirect to /ro:planner-worker.
category: development
allowed-tools: Read
---

# /ro:swarm

This is a thin alias for `/ro:planner-worker`. Both invocations resolve to the same behaviour.

**Use `/ro:planner-worker` directly** — it has the full skill body. `/ro:swarm` exists so the friendlier word also works.

See `~/.claude/plugins/cache/ronan-skills/<v>/skills/planner-worker/SKILL.md` for:

- When to use (and when not to)
- Quick start commands
- All 14 user stories (US-0 .. US-14) covering config grilling, planner, worker dispatch, DoD detection, merger, escalation, re-plan, `--github`, `--judge-agent`, `--afk`, `--workers N`, `--resume`, live status, postmortem
- Per-repo `.swarm.json` config
- File layout

## Invocation

```bash
/ro:swarm --prd <name>           # same as /ro:planner-worker --prd <name>
/ro:swarm --afk                  # same as /ro:planner-worker --afk
/ro:swarm --resume               # same as /ro:planner-worker --resume
```

All flags supported by `/ro:planner-worker` are supported here.
