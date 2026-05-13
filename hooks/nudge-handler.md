## How to handle RO_SKILLS_NUDGE markers

The ronan-skills plugin's SessionStart hook has emitted one or more `RO_SKILLS_NUDGE:` lines above. Each marker has the shape:

```
RO_SKILLS_NUDGE: <name> | <summary> | setup: <hint>
```

For the FIRST marker (only one nudge per session, even if multiple appear), ask the user via AskUserQuestion. Use the `<summary>` as the question body and offer exactly these three options:

1. **Set up now** — walk through the `<hint>` step by step. Once the setup is complete (env vars added, etc.), no state file write is needed; the hook's `nudge_check` will pass on the next session and the marker won't reappear.
2. **Remind me in 7 days** — write the snooze date to the state file:
   - macOS: `echo "remind:$(date -v+7d +%Y-%m-%d)" > ~/.claude/.ro/nudge-<name>`
   - Linux: `echo "remind:$(date -d '+7 days' +%Y-%m-%d)" > ~/.claude/.ro/nudge-<name>`
3. **Never ask again** — dismiss permanently: `echo "dismissed" > ~/.claude/.ro/nudge-<name>`

Replace `<name>` with the actual nudge name from the marker (e.g. `pushover`).

**Timing.** Ask near the top of the session, before diving into the user's request, so the answer doesn't get lost in a long thread. If the user opens the session mid-task ("fix this bug now"), defer the nudge until the task wraps up; never derail an active task to ask onboarding questions.

**One nudge per session.** If multiple markers appear, pick the first and handle it. The rest surface on the next session start. Piling up onboarding questions is the fastest way to get the user to dismiss everything.
