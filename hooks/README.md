# Hooks

This directory ships hooks that load automatically when the `ro` plugin is installed.

## SessionStart: onboarding nudges

`nudge-check.sh` runs at the start of every new Claude Code session. It checks each registered nudge in `nudges/*.sh` and, for any that are unconfigured and not snoozed/dismissed, emits a marker line into the session's initial context:

```
RO_SKILLS_NUDGE: <name> | <summary> | setup: <hint>
```

When any markers are emitted, the hook also appends the contents of `nudge-handler.md` to its stdout. That file tells the model exactly how to react: ask via AskUserQuestion with three options (set up now, remind in 7 days, never ask again) and write the answer to `~/.claude/.ro/nudge-<name>`. Shipping the handler in the plugin means the whole onboarding flow is portable, no per-user `CLAUDE.md` edits required.

### Adding a new nudge

Create `nudges/<feature>.sh`:

```bash
NUDGE_NAME="<feature>"
NUDGE_SUMMARY="One-line value proposition. Why does this matter to the user?"
NUDGE_SETUP_HINT="Concrete steps: where to sign up, what env vars to add to ~/.claude/.env, what skill to run after."

nudge_check() {
  # Return 0 if the user already has this set up (skip the nudge).
  # Return non-zero if the nudge should fire.
  [[ -n "${SOME_API_KEY:-}" ]]
}
```

That's it. No registration step; `nudge-check.sh` globs the directory at session start. The user's `~/.claude/.env` is sourced before nudges run, so checking env vars is fine.

### State file format

Lives at `~/.claude/.ro/nudge-<name>`. One of:

| Content              | Meaning                              |
| -------------------- | ------------------------------------ |
| `dismissed`          | Never nudge again.                   |
| `remind:YYYY-MM-DD`  | Silent until that date.              |
| *(file absent)*      | Eligible if `nudge_check` fails.     |

### Manual reset

To re-enable a previously-dismissed nudge: `rm ~/.claude/.ro/nudge-<name>`.

### Testing locally

Without affecting your real state:

```bash
TMP="$(mktemp -d)"
touch "$TMP/.env"
RO_SKILLS_ENV_FILE="$TMP/.env" RO_SKILLS_STATE_DIR="$TMP/state" \
  bash hooks/nudge-check.sh
```
