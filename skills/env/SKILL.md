---
name: env
description: Manage credentials INSIDE the active ~/.claude/.env file — read which token/account to use for a given app (Simplicity vs Dataforce vs Ronan-personal), add or update a secret WITHOUT it passing through the chat (an interactive Terminal window prompts for it), and track secrets that were exposed in a transcript so they get rotated. Sibling to /ro:context (which switches WHICH env file is active). Use when the user wants to add an API key/token/secret, asks "which credential do I use for X", needs the env organized/labelled, or a secret was pasted into the chat and should be rotated.
category: project-setup
argument-hint: [add <KEY> | which <app> | exposed | organize]
allowed-tools: Bash(bash *) Bash(ro *) Bash(grep *) Bash(readlink *) Read AskUserQuestion
---

# env — credential management inside the active env file

`/ro:context` decides **which** `~/.claude/.env.<context>` file is active. **`/ro:env` manages the credentials inside it**: reading the right one, adding new ones safely, keeping it organised, and tracking exposures. Resolve the active file with `ro context env` (cwd-aware); `~/.claude/.env` is a symlink to it.

## The ownership model (read this first)

Every section of the env file is tagged with one of three owners. Never guess — the tag tells you.

| Tag | What | Cloudflare account |
|---|---|---|
| `[SIMPLICITY]` | Simplicity Labs company infra. **Bare** names (`CLOUDFLARE_API_TOKEN`, `_ACCOUNT_ID`, `_ZONE_ID`) are the Simplicity defaults, kept bare for skill compatibility; `_SIMPLICITY` mirrors them. | `fcc16bad…` ("Ronan@simplicitylabs.io's Account") |
| `[DATAFORCE]` | The product (Simplicity × Taskforce). Runs on the Simplicity account; own keys always suffixed `_DATAFORCE`, or product-scoped (Google Ads, Shopify, Nango, Atlassian DAFO, ChatGPT GPT). | `fcc16bad…` (same account) |
| `[PERSONAL]` | Ronan's own side-projects, NOT Simplicity. Suffixes `_RONAN`, `_LEKKERTAAL`, `_ADHD`; also Pushover/Telegram/Neon-"factory"/VAPID. | `c421a1b2…` (ronanconnolly.dev / Tech@discopenguin.com) |

The file carries a **LEGEND + DEPLOY CHEAT-SHEET** at the top mirroring this. The dataforce repo's memory `reference_dataforce_cf_credentials` mirrors it too.

### Which credential for which deploy
| App | Token | Account |
|---|---|---|
| Dataforce | `CLOUDFLARE_API_TOKEN_DATAFORCE` | `CLOUDFLARE_ACCOUNT_ID_SIMPLICITY` |
| Simplicity site | `CLOUDFLARE_API_TOKEN` (=`_SIMPLICITY`) | `CLOUDFLARE_ACCOUNT_ID` |
| lekkertaal / adhd | `CLOUDFLARE_API_TOKEN_RONAN` \| `_ADHD` | `CLOUDFLARE_ACCOUNT_ID_RONAN` |

`which <app>` → just answer from the table above + `grep -iE '<app>' "$(ro context env)"`.

## Adding / updating a secret — NEVER paste it in the chat

**Default path (agent-driven):** launch an interactive Terminal window so the human types the secret there. The value never enters the conversation, never hits a tool result, never lands in argv/`ps`.

```bash
bash ~/Dev/ronan-skills/skills/env/scripts/add-secret.sh --launch ANTHROPIC_API_KEY_DATAFORCE DATAFORCE "Workspace key, dataforce chat"
```

That opens Terminal; the user pastes the value at a hidden `read -rs` prompt. The script then, on the **real** env file (symlink resolved):
- takes a timestamped `.bak.<ts>` backup first (non-destructive),
- **updates the line in place** if the key exists (value passed via env var, never argv), else **appends** a tagged `# [OWNER] …` block at the end,
- verifies the write and restores the backup if it failed.

**If the user is at the keyboard**, they can run it themselves: prefix with `!` in Claude Code, or run `bash …/add-secret.sh --interactive KEY OWNER "comment"` in any terminal.

**Rule:** if a user *does* paste a secret into the chat anyway, (1) still get it into the env (or wherever it belongs), and (2) immediately log it for rotation (next section) and tell them to rotate it — a value in the transcript is compromised.

## Tracking exposed secrets (rotation queue)

When a secret is exposed (pasted in chat, screenshotted, committed), log it:

```bash
bash ~/Dev/ronan-skills/skills/env/scripts/rotate-queue.sh add CLOUDFLARE_API_TOKEN_DATAFORCE env "re-pasted in chat 2026-05-23"
bash ~/Dev/ronan-skills/skills/env/scripts/rotate-queue.sh list      # see everything still to rotate
bash ~/Dev/ronan-skills/skills/env/scripts/rotate-queue.sh done CLOUDFLARE_API_TOKEN_DATAFORCE
```

Queue lives at `~/.claude/.secrets-rotate-queue.md` (gitignored). `list` also greps the active env for `CHAT-EXPOSED` / `ROTATE` comment markers. At the start of any session that will touch deploys/secrets, run `list` and nudge the user on anything still OPEN.

## Organising the env file

Keep it self-documenting:
- Every section header gets a `# --- [OWNER] … ---` tag.
- The top LEGEND + DEPLOY CHEAT-SHEET is the single source of truth for the taxonomy.
- Edit **comments and structure freely; never hand-edit a secret value** (use `add-secret.sh` so you don't see it and can't typo it). The file is a symlink — edit the resolved target (`readlink -f ~/.claude/.env`), not the link.
- New project? Pick the owner bucket, suffix the keys accordingly (`_DATAFORCE`, `_RONAN`, …), and add them via `add-secret.sh` with that OWNER tag.

## Relationship to other skills
- **`/ro:context`** — switches the active profile/file. `ro:env` operates within whatever it resolves.
- **`/ro:cf-ship`, `/ro:fly-deploy`, `/ro:cloudflare-dns`** — consume these credentials; point them at the cheat-sheet when they pick a token.
- **`/ro:setup-wizard`** — first-run onboarding; `ro:env` is the ongoing per-secret manager.

## Provenance
- 2026-05-23 — created after a session where secrets (Anthropic key, Dataforce CF token) were pasted directly into the chat and the agent kept getting confused about which Cloudflare token/account to use for Dataforce vs personal apps. The interactive-Terminal add flow keeps secrets out of the transcript; the ownership tags + legend remove the which-credential confusion.
