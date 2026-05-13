---
name: pushover
description: Send a push notification to Ronan's phone via the Pushover API. Use at the END of an AFK / night-shift / Ralph-loop / unattended /loop run so he knows the agent has stopped and is ready for the next thing. Do NOT fire this for ordinary interactive responses, only when the user has signalled they are away from keyboard. Reads PUSHOVER_APP_TOKEN and PUSHOVER_USER_KEY from ~/.claude/.env. Triggers on "AFK", "go AFK", "night shift", "kick off night shift", "run night shift", "/ro:matt-pocock-coding-workflow" in night-shift mode, "/ro:ralph" in night-shift mode, and any "/loop" with no interval. Also use whenever the user explicitly says "ping me", "notify me", "push me when done", "let me know when you're finished".
category: workflow
argument-hint: <message> [--title <title>] [--priority <-2..2>] [--sound <name>] [--url <url>] [--url-title <text>]
allowed-tools: Bash(bash *) Bash(curl *) Bash(python3 *) Bash(source *) Bash(set *) Bash(unset *) Read
---

# Pushover Notification

Sends a push notification to Ronan's phone via [Pushover](https://pushover.net/api). One curl call, one notification.

## When to fire

Use at the **end** of a run when Ronan is away from keyboard. The point is that he doesn't have to babysit the terminal: if night-shift mode stops 20 minutes in for any reason (waiting on input, finished early, crashed, blocked), the phone notification tells him to come back.

**Fire when any of these are true for the current session:**

- User said `AFK`, `go AFK`, `let's go AFK`, `afk run`, `I'm AFK`.
- User said `night shift`, `kick off night shift`, `run night shift`, `go night shift`, `setup night shift`, `human night shift`.
- `/ro:matt-pocock-coding-workflow` was invoked in **night-shift / AFK** mode (not interactive in-the-loop mode).
- `/ro:ralph` was invoked in **AFK / night-shift** mode (the autonomous variant).
- `/loop` was invoked with **no interval** (dynamic self-paced loop, almost always unattended).
- User explicitly asked to be pinged: "ping me when done", "notify me when finished", "let me know when you're ready".

**Do NOT fire when:**

- The user is clearly at-keyboard and interactive (normal back-and-forth).
- Mid-run progress updates. Only fire **once, at the end**, when the agent is genuinely handing control back. Otherwise the notifications become noise and lose their signal.
- The skill itself is being tested in an interactive session (the user will ask for a test explicitly).

If you're unsure whether the session is AFK, **don't fire**. False quiet beats false pings.

## Usage

```bash
# Basic — fired at end of a night-shift run
bash skills/pushover/scripts/notify.sh "night shift done — 7 stories merged, ready for review"

# With a title (shows in bold at the top of the notification)
bash skills/pushover/scripts/notify.sh "ralph loop finished" --title "Night shift"

# Higher priority, custom sound (good for "you should look NOW")
bash skills/pushover/scripts/notify.sh "blocked on input after 3 stories" \
  --title "Night shift paused" --priority 1 --sound magic

# Attach a clickable URL (e.g. the PR to review)
bash skills/pushover/scripts/notify.sh "PR ready" \
  --url "https://github.com/RonanCodes/foo/pull/42" --url-title "Open PR"
```

## Anatomy of a good end-of-run message

Keep it scannable. Three things in this order:

1. **What state the run is in** — done, paused, blocked, crashed.
2. **One concrete metric** — `7 stories merged`, `3 PRs open`, `failed on story #4`.
3. **What Ronan needs to do next** — `ready for review`, `needs input`, `check Sentry`.

Examples that work:

- `night shift done — 7 stories merged, 0 failed, ready for review`
- `ralph loop paused after story 4 — needs your call on the auth approach`
- `night shift crashed at story 2 — tsc errors in src/api/billing.ts`
- `/loop finished — 12 PRs drained, queue empty`

Examples to avoid (vague, low-signal):

- `done` (done with what?)
- `finished the task successfully` (filler)
- `please review the latest changes when you have a moment` (too long, too polite)

## Priority and sound

Default priority `0`, default sound is Ronan's Pushover account default. Bump priority to `1` for "blocked, needs human" so it bypasses quiet hours; leave at `0` for "done, no rush".

Full sound list: <https://pushover.net/api#sounds>. `magic` and `cosmic` are good attention-getters; `none` for silent.

## Errors

- `PUSHOVER_APP_TOKEN not set` — add it to `~/.claude/.env`.
- `PUSHOVER_USER_KEY not set` — same.
- Response `{"status":0,"errors":[...]}` — script exits non-zero and prints the body. Common cause: token typo or user has Pushover delivery paused.

## How this skill stays always-on

The trigger rule lives in `~/CLAUDE.md` under **Pushover Notifications**, which is loaded into every session. That global rule tells Claude *when* to fire; this SKILL.md describes *how*. Don't move the trigger logic in here; the global file is what guarantees Claude actually remembers to send the ping at end-of-run, even if the skill description scrolls out of the window.
