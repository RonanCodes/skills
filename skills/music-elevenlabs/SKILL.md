---
name: music-elevenlabs
description: Generate background music from text prompts via ElevenLabs Music API. Outputs MP3 files up to 10 minutes. Use for video soundtracks, podcast intros, ambient backgrounds.
user-invocable: true
allowed-tools: Bash(curl *) Bash(ffmpeg *) Bash(which *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(wc *) Bash(python3 *) Read Write Glob Grep
content-pipeline:
  - pipeline:audio
  - platform:agnostic
  - role:primitive
---

# Music — ElevenLabs

Generate music tracks from text prompts using ElevenLabs' Eleven Music API. Outputs an MP3 file — from a 3-second jingle to a 10-minute background track.

## Usage

```
/music-elevenlabs "upbeat electronic dance track with synth leads" [--duration <seconds>] [--output <path>]
/music-elevenlabs "calm ambient piano for a product demo video" --duration 60 --instrumental
/music-elevenlabs --plan composition.json --output soundtrack.mp3
```

- `--duration` — length in seconds (3–600). Default: 30.
- `--output` — output file path. Default: `/tmp/music-elevenlabs-<timestamp>.mp3`.
- `--instrumental` — force instrumental output (no vocals). Default: false.
- `--plan` — path to a JSON composition plan for detailed control (mutually exclusive with text prompt).
- `--seed` — integer seed for reproducibility (only with `--plan`).
- `--format` — output format. Default: `mp3_44100_128`.

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

## Step 2: Build Request

### Simple prompt mode (default)

```bash
PROMPT="$1"
DURATION_MS=$(( ${DURATION:-30} * 1000 ))   # API takes milliseconds
INSTRUMENTAL="${INSTRUMENTAL:-false}"
MODEL="music_v1"
FORMAT="${FORMAT:-mp3_44100_128}"
OUTPUT="${OUTPUT_PATH:-/tmp/music-elevenlabs-$(date +%s).mp3}"

# Validate duration (3s–600s = 3000ms–600000ms)
if [ "$DURATION_MS" -lt 3000 ] || [ "$DURATION_MS" -gt 600000 ]; then
  echo "❌ Duration must be between 3 and 600 seconds"
  exit 1
fi
```

### Composition plan mode (`--plan`)

A composition plan gives fine-grained control over sections, tempo, and instrumentation:

```json
{
  "sections": [
    {
      "text": "Gentle piano intro, slow tempo, ambient feel",
      "duration_ms": 15000
    },
    {
      "text": "Build energy, add drums and bass, moderate tempo",
      "duration_ms": 30000
    },
    {
      "text": "Climax with full orchestra, fast tempo, epic feel",
      "duration_ms": 20000
    },
    {
      "text": "Wind down, return to piano, fade out",
      "duration_ms": 15000
    }
  ]
}
```

Section durations: 3000ms–120000ms each. Total: 3000ms–600000ms.

## Step 3: Call the API

```bash
if [ -n "$PLAN_FILE" ]; then
  # Composition plan mode
  PLAN=$(cat "$PLAN_FILE")
  curl -s -X POST "https://api.elevenlabs.io/v1/music?output_format=${FORMAT}" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
plan = json.loads('''$PLAN''')
data = {
    'composition_plan': plan,
    'model_id': 'music_v1',
    'respect_sections_durations': True
}
print(json.dumps(data))
")" \
    --output "$OUTPUT"
else
  # Simple prompt mode
  curl -s -X POST "https://api.elevenlabs.io/v1/music?output_format=${FORMAT}" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
data = {
    'prompt': '''$PROMPT''',
    'music_length_ms': $DURATION_MS,
    'model_id': 'music_v1',
    'force_instrumental': $INSTRUMENTAL
}
print(json.dumps(data))
")" \
    --output "$OUTPUT"
fi
```

**Note:** Music generation can take 30–120 seconds for longer tracks. The API streams the response.

## Step 4: Verify Output

```bash
if [ ! -f "$OUTPUT" ] || [ "$(wc -c < "$OUTPUT")" -lt 1000 ]; then
  echo "❌ Music generation failed. Response:"
  cat "$OUTPUT" 2>/dev/null
  exit 1
fi

DURATION_ACTUAL=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null | cut -d. -f1)
SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
```

## Step 5: Report

```
✅ Music generated
   Prompt:      <first 80 chars>...
   Model:       music_v1
   Duration:    <N>s
   Instrumental: <true|false>
   Size:        <N> KB
   Output:      <output path>
   Play:        open <output path>
```

## Test Command

```bash
# Quick test — generates a 5-second jingle
export $(grep ELEVENLABS_API_KEY ~/.claude/.env)
curl -s -X POST "https://api.elevenlabs.io/v1/music" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "short cheerful jingle", "music_length_ms": 5000, "model_id": "music_v1", "force_instrumental": true}' \
  --output /tmp/music-test.mp3 && \
echo "✅ API key works" && open /tmp/music-test.mp3
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ELEVENLABS_API_KEY` | yes | — | API key from elevenlabs.io/app/settings/api-keys |

## Constraints

- **Duration**: 3–600 seconds (3s–10min)
- **Section duration** (composition plan): 3–120 seconds each
- **Model**: `music_v1` is currently the only available model
- **Paid tier required**: Music generation is available on paid plans
- **Generation time**: longer tracks take proportionally longer to generate

## Example Prompts

| Use Case | Prompt | Duration |
|----------|--------|----------|
| **Video intro** | "cinematic orchestral buildup, epic and inspiring" | 10s |
| **Podcast intro** | "warm jazzy lo-fi beat with soft piano" | 15s |
| **Product demo** | "clean modern corporate background, upbeat but subtle" | 60s |
| **Tutorial** | "calm ambient electronic, minimal and focused" | 120s |
| **Trailer** | "dark dramatic tension building to explosive climax" | 30s |
| **Outro** | "gentle acoustic guitar fade out, peaceful" | 10s |

## Integration with Other Skills

- `generate-video` — background music for Remotion video compositions
- `sfx-elevenlabs` — layer SFX over music for full audio design
- `tts-elevenlabs` — combine narration with background music
- `audio-mix` — mix voice + music + SFX into a final audio track

## See Also

- [ElevenLabs Music API](https://elevenlabs.io/docs/api-reference/music/compose)
- [ElevenLabs Music overview](https://elevenlabs.io/docs/overview/capabilities/music)
- [Music quickstart](https://elevenlabs.io/docs/eleven-api/guides/cookbooks/music/quickstart)
