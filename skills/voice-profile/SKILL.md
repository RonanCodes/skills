---
name: voice-profile
description: Build a portable voice profile (markdown file) by running a 100-question taste interview across 7 categories. Output is consumable by any AI to reproduce the user's voice. Resumable across sessions. Based on Ruben Hassid's "I am just a text file" methodology (Jan 2026).
category: writing
argument-hint: <start | resume | status | compile | show | path>
allowed-tools: Bash(jq *) Bash(cat *) Bash(open *) Read Write Edit
---

# Voice Profile

Build a portable `voice-profile.md` that any AI can read to reproduce the user's writing voice. Based on Hassid's methodology (Jan 2026): voice is mostly **refusals**, not preferences, so the interview captures what the user would never write.

**Source documents:**
- Online: https://ruben.substack.com/p/i-am-just-a-text-file
- Vault concept page (user only): [ai-research:voice-extraction-methodology](obsidian://open?vault=llm-wiki-ai-research&file=wiki%2Fconcepts%2Fvoice-extraction-methodology)

## Usage

```
/ro:voice-profile start         # begin a new interview (or resume if in progress)
/ro:voice-profile resume        # explicit resume — pick up where you left off
/ro:voice-profile status        # show progress (questions answered per category)
/ro:voice-profile compile       # build voice-profile.md from current state
/ro:voice-profile show          # cat the compiled voice-profile.md
/ro:voice-profile path          # print canonical file paths (state + output)
```

The interview is ~100 questions and takes 60–120 minutes. **It is meant to be run in chunks across multiple sessions.** State persists between sessions.

## How the interview works

Claude (you, reading this) conducts the interview live in chat. The user answers in chat. Their answers get persisted to a state file by you (Edit/Write the JSON directly).

### Categories and counts

| # | Category | Questions | Probes (the area to interrogate) |
|---|----------|-----------|----------------------------------|
| 1 | Beliefs & Contrarian Takes | 15 | Beliefs others in the field don't share; hot takes; conventional wisdom they think is wrong |
| 2 | Writing Mechanics | 20 | Sentence structures, openers/closers, punctuation/formatting habits, words they overuse / love / never use |
| 3 | Aesthetic Crimes | 15 | What makes them cringe in others' writing; nails-on-chalkboard phrases; lazy content patterns |
| 4 | Voice & Personality | 15 | Humor, serious vs casual, handling disagreement, sound when excited vs skeptical |
| 5 | Structural Preferences | 15 | How they organise ideas, lists/headers/bullets, transitions, default content shapes |
| 6 | Hard Nos | 10 | Topics they'd never write about, approaches they'd never take, lines they won't cross |
| 7 | Red Flags | 10 | What makes them distrust a piece of content immediately; signals someone doesn't know what they're talking about |
| **Total** | | **100** | |

Hassid did not publish the verbatim 100 questions. Generate them dynamically within each category, guided by the probes. This adapts to the user's prior answers and avoids overlap.

### Six interview rules (load into your behavior)

1. **ONE question at a time.** Wait for the response before asking the next.
2. **Push back on vague answers.** If they say "I write conversationally," ask: "Conversational how? Give me a sentence you've written that captures it, and one that's lazy-conversational."
3. **Demand specific examples.** Quotes from real things they've written. Real phrases they hate. Real conventional-wisdom claims they reject.
4. **Call out contradictions.** If Q3 contradicts Q12, surface it: "You said X earlier, now you're saying Y — which is it?"
5. **Follow interesting threads deeper.** If a one-line answer hints at something rich, drill in for 1–2 follow-ups before moving on.
6. **Don't accept "I don't know" easily — reframe.** "If you had to pick one, which side of this do you lean?" or "What would your gut answer be even if you're not 100% sure?"

The point is rich, specific answers. A 3-word vague answer is worthless. A 4-paragraph specific answer is the goal.

## Dispatch

| Arg | Behavior |
|-----|----------|
| `start` | If no state exists, run `scripts/start.sh` to create one (asks for user's name first), then begin Q1 of category 1. If state exists with status `in_progress`, behave as `resume`. |
| `resume` | Read state, print summary ("You're 23 of 100 done, currently in Category 2: Writing Mechanics"), then ask the next unanswered question. |
| `status` | Run `scripts/status.sh`. Print only — do not ask a question. |
| `compile` | Run `scripts/compile.sh`. Compile current state into `voice-profile.md`. Works even if interview is incomplete (will mark unanswered sections). |
| `show` | Run `scripts/show.sh` to print the compiled file. |
| `path` | Run `scripts/path.sh` to print where state and output live. |

## Recording answers (your job during the interview)

After each user answer that has passed the rules (specific, exampled, non-contradictory), update the state file at `~/.claude/voice-profile-state.json` directly via the Edit tool. Append a new entry to the category's `answered` array:

```json
{
  "q": "<the question you asked>",
  "a": "<their answer, verbatim>",
  "follow_ups": [
    {"q": "<your push-back>", "a": "<their refined answer>"}
  ],
  "answered_at": "<ISO 8601 timestamp>"
}
```

Then ask the next question. Do not batch — record after every settled answer so the work is never lost mid-session.

When a category finishes (e.g., 15/15 in Beliefs):
1. Acknowledge the milestone ("That's category 1 done.").
2. Summarize 2–3 things you learned about their voice from that category.
3. Ask if they want to continue or pause. If pause: stop, remind them of `/ro:voice-profile resume`.

When all 100 are done, run `scripts/compile.sh` and tell them where the file is.

## First-time setup

No setup. The skill creates `~/.claude/voice-profile-state.json` on `start` and `~/.claude/voice-profile.md` on `compile`. Both are gitignored by default.

## Vault- or project-backed state (recommended for durable / wiki-integrated use)

State and output default to `~/.claude/` but are overridable via env vars (see `scripts/common.sh`):

- `VOICE_PROFILE_STATE` — path to the JSON state file
- `VOICE_PROFILE_OUTPUT` — path to the compiled markdown

To keep a profile inside an llm-wiki vault (versioned, browsable in Obsidian, resumable across machines), export both before any subcommand:

```bash
export VOICE_PROFILE_STATE="$PWD/vaults/llm-wiki-voice/scratchpad/voice-profile-state.json"
export VOICE_PROFILE_OUTPUT="$PWD/vaults/llm-wiki-voice/wiki/entities/voice-profile-<name>.md"
```

**Resume discovery (important).** When the user asks in natural language to "continue / pick up my voice profile" — without typing `/ro:voice-profile resume` — do NOT start a fresh interview. Locate existing state first, in this order:

1. A loaded memory note about a paused voice interview (it names the state path).
2. `vaults/*/scratchpad/voice-profile-state.json` under the current repo.
3. The default `~/.claude/voice-profile-state.json`.

If a state file with `status: in_progress` is found, export `VOICE_PROFILE_STATE`/`VOICE_PROFILE_OUTPUT` to point at it, run `status` to reload progress, then behave as `resume`.

## Output format

`voice-profile.md` follows Hassid's template:

```
# VOICE PROFILE: <Name>
## Core Identity (2-3 sentence essence — only summary section)
## SECTION 1: BELIEFS & CONTRARIAN TAKES (Q1–Q15 with full answers)
## SECTION 2: WRITING MECHANICS (Q16–Q35)
## SECTION 3: AESTHETIC CRIMES (Q36–Q50)
## SECTION 4: VOICE & PERSONALITY (Q51–Q65)
## SECTION 5: STRUCTURAL PREFERENCES (Q66–Q80)
## SECTION 6: HARD NOS (Q81–Q90)
## SECTION 7: RED FLAGS (Q91–Q100)
## QUICK REFERENCE CARD
  - Always
  - Never
  - Signature Phrases & Structures
  - Voice Calibration (key quotes from the interview)
## HOW TO USE THIS DOCUMENT (ANTI-OVERFITTING GUIDE)
  - Frequency labels: HARD RULE / STRONG TENDENCY (70–80%) / LIGHT PREFERENCE
  - Litmus test: "Does this sound like something I would actually write, or does it sound like an AI trying very hard to imitate me?"
  - Format adaptation: tweet ≠ newsletter ≠ LinkedIn ≠ long-form
  - Spirit Over Letter
## INSTRUCTIONS FOR CLAUDE (the file is the context — every prompt should start by reading it)
```

The Quick Reference Card and Anti-Overfitting Guide are derived from the answers, not asked directly. Compile them after the 100 are done.

## What this skill does NOT do

- **Does not write the questions for you.** You generate them in chat, using the category probes as your guide.
- **Does not auto-resume.** If state exists, the user still types `start` or `resume` — no surprise re-engagement on every session.
- **Does not publish the file anywhere.** It writes to `~/.claude/voice-profile.md` only. The user is responsible for copying it to other AIs / hosts.
- **Does not produce per-format variants** (tweet voice vs LinkedIn voice vs newsletter voice). The single file documents tendencies; the consumer (e.g. `/ro:write-copy` or a future `/draft` skill) decides which tendencies apply per format.

## See also

- `ro:write-copy` — once `voice-profile.md` exists, this skill should read it as additional context for any drafting work.
- `reference.md` — full question-bank guidance, output template, anti-overfitting layer detail.
- Original methodology: https://ruben.substack.com/p/i-am-just-a-text-file
