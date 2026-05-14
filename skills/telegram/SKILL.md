---
name: telegram
description: Telegram bot setup, one-way send/notify, and two-way listener that pipes incoming messages to a Claude Code session. Subcommands - setup (walks BotFather and captures bot token + chat_id), send (one shot message), notify (end-of-run ping with the same firing rule as /ro:pushover), listen (long-poll loop that runs `claude -p` per incoming message in a configured working dir and replies with the output). Use when Ronan asks to "set up a telegram bot", "telegram me when done", "ping me on telegram", "start the telegram listener", "let me query claude from my phone", or any /ro:telegram subcommand. Reads TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, TELEGRAM_LISTEN_CWD from ~/.claude/.env.
category: workflow
argument-hint: <subcommand> [args] - one of - setup | send <msg> | notify <msg> [--title T] | listen [--cwd PATH] [--daemon]
allowed-tools: Bash(bash *) Bash(curl *) Bash(python3 *) Bash(jq *) Bash(source *) Bash(set *) Bash(unset *) Bash(launchctl *) Read Edit Write
---

# Telegram

Talk to a personal Telegram bot from anywhere. Send pings out, receive messages in, dispatch incoming messages to `claude -p` headless and reply with the output.

Sister skill to `/ro:pushover`. Pushover is one-way push only. Telegram is bidirectional and lets you query the agent while you are away from the laptop.

## Subcommands

```bash
/ro:telegram setup              # one-time bot creation, captures token + chat_id
/ro:telegram send <msg>         # raw send, no envelope
/ro:telegram send-photo <path>  # send an image (auto-falls back to sendDocument on dimension limit)
/ro:telegram notify <msg> [...] # end-of-run ping with title (mirrors pushover)
/ro:telegram listen             # foreground long-poll loop
/ro:telegram listen --daemon    # install launchd plist, run on login (mac)
/ro:telegram listen --stop      # tear down the daemon
```

All four wrap shell scripts in `scripts/`. The skill itself is mostly orchestration plus the firing rule below.

## When to fire `notify`

Same trigger list as `/ro:pushover`. Fire BOTH in sequence at end of an AFK run so Ronan gets the redundant signal across both channels while we are still figuring out which one he prefers.

Fire when ANY of these are true for the current session:

1. User said `AFK`, `go AFK`, `afk run`, `I'm AFK`.
2. User said `night shift`, `kick off night shift`, `run night shift`.
3. `/ro:matt-pocock-coding-workflow` was invoked in AFK / night-shift mode.
4. `/ro:ralph`, `/ro:planner-worker`, `/ro:swarm`, or `/agentic-e2e-flow` was invoked against a real backlog (not `--plan-only`, not `--mode single`).
5. `/loop` was invoked with NO interval (self-paced).
6. User explicitly said `ping me`, `notify me when done`, `let me know when finished`.

Do NOT fire on ordinary interactive turns. Notifications only have signal if they are rare.

## Setup (one-time)

Skill walks you through it. The flow:

1. Open Telegram, message `@BotFather`.
2. Send `/newbot`, pick a display name (e.g. `Ronan Claude Bot`) and a unique username ending in `bot` (e.g. `ronan_claude_bot`).
3. BotFather replies with an HTTP API token. Paste it back to the skill.
4. Skill writes `TELEGRAM_BOT_TOKEN` to `~/.claude/.env` and starts polling `/getUpdates`.
5. Send any message to your bot from Telegram.
6. Skill captures your `chat_id`, writes `TELEGRAM_CHAT_ID`, sends a confirmation back via `sendMessage`. Done.

Run it:

```bash
bash skills/telegram/scripts/setup.sh
```

To re-run setup (e.g. new bot), delete the existing keys from `~/.claude/.env` first.

## Send / notify

```bash
bash skills/telegram/scripts/send.sh "hello from claude"

bash skills/telegram/scripts/notify.sh "night shift done - 7 stories merged" \
  --title "Night shift"
```

`notify.sh` is a thin wrapper that prefixes the title in bold (`*Title*\n\nmessage`) and uses Markdown parse mode. `send.sh` is plain text.

## Send photo

```bash
bash skills/telegram/scripts/send-photo.sh ~/Pictures/foo.jpg --caption "screenshot"
bash skills/telegram/scripts/send-photo.sh https://example.com/img.png
bash skills/telegram/scripts/send-photo.sh ~/big.jpg --as-file  # force sendDocument
```

Telegram's `sendPhoto` compresses and caps at ~10000px combined width+height. The script auto-detects `PHOTO_INVALID_DIMENSIONS` / oversize errors and retries via `sendDocument`, which sends the file uncompressed with no dimension cap (50 MB limit). Use `--as-file` to skip the photo attempt entirely.

Message envelope rules - keep it scannable, three things in order:

1. State (done / paused / blocked / crashed).
2. One concrete metric (`7 stories merged`, `failed on story #4`).
3. What to do next (`ready for review`, `needs your call on auth approach`).

Examples that work:

- `night shift done - 7 stories merged, 0 failed, ready for review`
- `ralph loop paused after story 4 - needs your call on the auth approach`
- `loop finished - 12 PRs drained, queue empty`

## Listen (two-way)

Foreground long-poll loop. For every incoming message from `TELEGRAM_CHAT_ID`:

1. Run `claude -p "<message>"` in `TELEGRAM_LISTEN_CWD` (env var, default `$HOME/Dev`).
2. Capture stdout.
3. Reply on Telegram with the output, replying to the original message.

```bash
# foreground (testing / one session)
bash skills/telegram/scripts/listen.sh

# point at a specific working dir for this run
bash skills/telegram/scripts/listen.sh --cwd ~/Dev/ai-projects/llm-wiki

# daemon mode (macOS launchd, persists across reboot while laptop is awake)
bash skills/telegram/scripts/listen.sh --daemon

# stop the daemon
bash skills/telegram/scripts/listen.sh --stop
```

### Security

Two layers:

1. **chat_id allowlist.** The listener REJECTS messages from any `chat_id` other than `TELEGRAM_CHAT_ID`. Anyone who knows the bot username can DM it; without this check every random message becomes a Claude Code invocation in your working tree. Do not disable.
2. **--dangerously-skip-permissions.** The listener passes this to `claude -p` because launchd has no TTY to prompt for tool-call approvals. Without it, every Read / Bash / Edit hangs or errors and the bot is effectively text-completion-only. With it, the bot can do anything Claude Code can do as you, in `TELEGRAM_LISTEN_CWD`. The chat_id allowlist is what stops random Telegram users from exploiting that.

If you ever lose your phone or Telegram account is compromised, `bash skills/telegram/scripts/listen.sh --stop` to take the daemon down, then revoke the bot in BotFather (`/revoke`).

If you need multi-user later, change `TELEGRAM_CHAT_ID` to a comma list and update the filter in `listen.sh`. To make the bot read-only, remove `--dangerously-skip-permissions` from the dispatch line in `listen.sh`.

### Truncation

Telegram caps `sendMessage` at 4096 chars. `listen.sh` splits long replies into multiple messages, suffixed `(part N/M)`.

### What gets run

The dispatch shape:

```bash
cd "$TELEGRAM_LISTEN_CWD"
claude -p --session-id "$SESSION_UUID" "$INCOMING_MESSAGE"
```

Conversational continuity. The listener keeps a "current session UUID" in `~/.claude/telegram-session.json` and passes it via `--session-id` on every call. Same UUID twice means `claude` resumes the prior conversation, so a back-and-forth on Telegram shares one thread instead of starting cold every message.

Session rotation rules:

- Send `/new` (or `/reset`) in Telegram to force a fresh session UUID. Bot confirms with `new session started`.
- Idle auto-rotate. If no message arrived within `TELEGRAM_SESSION_IDLE_HOURS` (default 6), the next message starts a fresh UUID. Prevents unbounded context growth on neglected threads.
- Daemon restart preserves the session file, so the active thread survives launchd reloads.

Other commands the listener understands:

- `/new` or `/reset` - rotate to a fresh session.
- `/cwd` - reply with the current `TELEGRAM_LISTEN_CWD`.
- `!<shell command>` - run raw shell instead of dispatching to claude. e.g. `!git status`. Output goes back as a reply.

State file shape:

```json
{
  "session_id": "5a8e3b7c-...",
  "started_at": "2026-05-14T10:00:00Z",
  "last_message_at": "2026-05-14T10:42:11Z",
  "message_count": 7
}
```

## Always-on (the dream)

v1 of this skill ships with launchd-daemon support, so the listener auto-starts when you log in and runs as long as your laptop is awake.

v2 (separate work) ports the listener to the `factory` Pi substrate so the bot is reachable when the laptop is closed. That ties into the existing factory design (Pi + CF Sandbox + GH issues intake). When that lands, this skill points its `--daemon` flag at the Pi instead of installing launchd locally.

Until v2: laptop must be awake for the listener to respond. The launchd plist sets `KeepAlive` so it auto-restarts on crash.

## Env vars (in `~/.claude/.env`)

```
# --- telegram ---
TELEGRAM_BOT_TOKEN=123456:ABC-defGhIjk...
TELEGRAM_CHAT_ID=1234567890
TELEGRAM_LISTEN_CWD=/Users/ronan/Dev
```

`setup.sh` writes the first two. `TELEGRAM_LISTEN_CWD` is optional; defaults to `$HOME/Dev` if absent.

## Errors

- `TELEGRAM_BOT_TOKEN not set` - run `/ro:telegram setup`.
- `TELEGRAM_CHAT_ID not set` - same.
- `Unauthorized` from Telegram API - token is wrong or bot was deleted in BotFather.
- `Forbidden: bot was blocked by the user` - you blocked the bot in Telegram. Unblock and resend.
- `claude: command not found` in listener output - Claude Code CLI is not on PATH for the launchd context. Fix in the plist `EnvironmentVariables` block.

## How this stays always-on (firing rule)

The trigger rule for `notify` lives in `~/CLAUDE.md` under "Phone Notifications", loaded into every session. That global rule tells Claude when to fire; this SKILL.md describes how. Same pattern as `/ro:pushover`.
