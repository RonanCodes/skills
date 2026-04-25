---
name: tts-elevenlabs
description: Text-to-speech via ElevenLabs API. Converts text or a script file to high-quality MP3. Standalone utility — also called by generate-podcast and generate-video for voiceover.
user-invocable: true
allowed-tools: Bash(curl *) Bash(ffmpeg *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(wc *) Read Write Glob Grep
content-pipeline:
  - pipeline:audio
  - platform:agnostic
  - role:primitive
---

# TTS — ElevenLabs

Convert text to studio-quality speech via the ElevenLabs API. Outputs an MP3 file. Can be used standalone or called by `generate-podcast` and `generate-video` as their TTS backend.

## Usage

```
/tts-elevenlabs "Text to speak" [--voice <name|id>] [--output <path>] [--model <id>]
/tts-elevenlabs --file script.md [--voice <name|id>] [--output <path>]
```

- `--voice` — ElevenLabs voice name or ID. Default: `Rachel`. Common voices: `Rachel`, `Adam`, `Antoni`, `Bella`, `Domi`, `Elli`, `Josh`.
- `--output` — output file path. Default: `/tmp/tts-elevenlabs-<timestamp>.mp3`.
- `--model` — ElevenLabs model ID. Default: `eleven_multilingual_v2`. Options: `eleven_monolingual_v1`, `eleven_multilingual_v2`, `eleven_turbo_v2_5`.
- `--file` — read text from a file instead of inline argument. Strips markdown formatting before sending.

## Step 1: API Key Check

```bash
if [ -z "$ELEVENLABS_API_KEY" ]; then
  echo "❌ ELEVENLABS_API_KEY not set."
  echo ""
  echo "Get your key at: https://elevenlabs.io/app/settings/api-keys"
  echo "Then set it:     export ELEVENLABS_API_KEY=sk_..."
  echo "Or add to:       ~/.claude/.env"
  exit 1
fi
```

The key should be in the environment or in `~/.claude/.env` (which Claude Code loads automatically).

## Step 2: Resolve Voice

ElevenLabs uses voice IDs internally. Map common names to IDs:

```bash
VOICE_NAME="${VOICE:-Rachel}"

# Resolve name → ID via the voices endpoint (cached for the session)
VOICES_CACHE="/tmp/elevenlabs-voices-cache.json"
if [ ! -f "$VOICES_CACHE" ] || [ "$(find "$VOICES_CACHE" -mmin +60 2>/dev/null)" ]; then
  curl -s "https://api.elevenlabs.io/v1/voices" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" > "$VOICES_CACHE"
fi

VOICE_ID=$(jq -r --arg name "$VOICE_NAME" \
  '.voices[] | select(.name == $name) | .voice_id' "$VOICES_CACHE" | head -1)

# If no match, assume the user passed a raw voice ID
[ -z "$VOICE_ID" ] && VOICE_ID="$VOICE_NAME"
```

## Step 3: Prepare Text

```bash
if [ -n "$FILE_INPUT" ]; then
  # Strip markdown formatting for cleaner speech
  TEXT=$(sed -E '
    s/^#{1,6} //        # strip heading markers
    s/\*\*([^*]+)\*\*/\1/g   # bold → plain
    s/\*([^*]+)\*/\1/g       # italic → plain
    s/`([^`]+)`/\1/g         # code → plain
    s/\[([^\]]+)\]\([^)]+\)/\1/g  # links → text only
    s/^[-*] //           # strip list markers
    /^---$/d             # remove horizontal rules
    /^```/,/^```/d       # remove code blocks
  ' "$FILE_INPUT")
else
  TEXT="$INLINE_TEXT"
fi

# ElevenLabs has a 5000 char limit per request. Split if needed.
CHAR_COUNT=$(echo "$TEXT" | wc -c | tr -d ' ')
```

## Step 4: Call the API

```bash
MODEL="${MODEL_ID:-eleven_multilingual_v2}"
OUTPUT="${OUTPUT_PATH:-/tmp/tts-elevenlabs-$(date +%s).mp3}"

if [ "$CHAR_COUNT" -le 5000 ]; then
  # Single request
  curl -s "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg text "$TEXT" --arg model "$MODEL" \
      '{text: $text, model_id: $model, voice_settings: {stability: 0.5, similarity_boost: 0.75}}')" \
    --output "$OUTPUT"
else
  # Split into chunks at sentence boundaries, render each, concatenate
  # Split on `. ` or `\n\n`, keeping chunks under 4500 chars
  CHUNK_DIR="/tmp/tts-elevenlabs-chunks-$$"
  mkdir -p "$CHUNK_DIR"
  
  # Python one-liner to split text into chunks
  python3 -c "
import sys, textwrap
text = sys.stdin.read()
chunks = []
current = ''
for sentence in text.replace('\n\n', '. ').split('. '):
    if len(current) + len(sentence) > 4500:
        chunks.append(current)
        current = sentence
    else:
        current += ('. ' if current else '') + sentence
if current:
    chunks.append(current)
for i, chunk in enumerate(chunks):
    with open(f'$CHUNK_DIR/chunk_{i:03d}.txt', 'w') as f:
        f.write(chunk)
" <<< "$TEXT"

  # Render each chunk
  for chunk_file in "$CHUNK_DIR"/chunk_*.txt; do
    chunk_text=$(cat "$chunk_file")
    chunk_mp3="${chunk_file%.txt}.mp3"
    curl -s "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
      -H "xi-api-key: $ELEVENLABS_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg text "$chunk_text" --arg model "$MODEL" \
        '{text: $text, model_id: $model, voice_settings: {stability: 0.5, similarity_boost: 0.75}}')" \
      --output "$chunk_mp3"
  done

  # Concatenate with ffmpeg
  ls "$CHUNK_DIR"/chunk_*.mp3 | sed 's/^/file /' > "$CHUNK_DIR/concat.txt"
  ffmpeg -f concat -safe 0 -i "$CHUNK_DIR/concat.txt" -codec:a copy "$OUTPUT" -y 2>/dev/null
  rm -rf "$CHUNK_DIR"
fi
```

## Step 5: Verify Output

```bash
if [ ! -f "$OUTPUT" ] || [ "$(wc -c < "$OUTPUT")" -lt 100 ]; then
  echo "❌ TTS failed. Response may contain an error message:"
  cat "$OUTPUT" 2>/dev/null
  exit 1
fi

DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null | cut -d. -f1)
```

## Step 6: Report

```
✅ TTS complete
   Voice:    <voice name> (<voice id>)
   Model:    <model id>
   Input:    <char count> characters
   Duration: <seconds>s
   Output:   <output path>
   Play:     afplay <output path>
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ELEVENLABS_API_KEY` | yes | — | API key from elevenlabs.io/app/settings/api-keys |
| `ELEVENLABS_VOICE_A` | no | `Rachel` | Default voice for single-host / host A |
| `ELEVENLABS_VOICE_B` | no | `Adam` | Default voice for host B (two-voice mode) |

## Cost Estimate

ElevenLabs charges per character:
- **Starter** ($5/mo): 30,000 chars/mo
- **Creator** ($22/mo): 100,000 chars/mo
- **Pro** ($99/mo): 500,000 chars/mo

A typical 6-minute podcast script is ~5,000 characters ≈ $0.30 on pay-as-you-go.

## Integration with Other Skills

`generate-podcast` already checks for `ELEVENLABS_API_KEY` and uses it as the top-priority TTS backend. This skill provides the same capability as a standalone tool.

`generate-video --voiceover` chains through `generate-podcast`, which in turn uses this backend when available.

## See Also

- `.claude/skills/generate-podcast/SKILL.md` — uses ElevenLabs as Tier 1 TTS backend
- `.claude/skills/generate-video/SKILL.md` — optional voiceover via podcast pipeline
- [ElevenLabs API docs](https://elevenlabs.io/docs/api-reference/text-to-speech)
