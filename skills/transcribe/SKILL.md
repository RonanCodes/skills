---
name: transcribe
description: Transcribe audio or video files to text via OpenAI Whisper API or local whisper-cpp. Standalone utility — also used by ingest-video for meeting recordings and screen captures.
user-invocable: true
allowed-tools: Bash(curl *) Bash(ffmpeg *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(wc *) Bash(python3 *) Read Write Glob Grep
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:primitive
---

# Transcribe

Convert audio or video files to text using OpenAI Whisper (API or local). Outputs a timestamped transcript as markdown.

## Usage

```
/transcribe <file-path> [--output <path>] [--format text|srt|vtt|json] [--language <code>]
/transcribe <file-path> --vault <name>  # saves to vault's raw/ folder
```

- `--output` — output path. Default: `<input-stem>-transcript.md`.
- `--format` — output format. Default: `text`. Options: `text` (plain), `srt` (subtitles), `vtt` (web subtitles), `json` (timestamps + segments).
- `--language` — ISO 639-1 code (e.g. `en`, `nl`, `de`). Auto-detected if omitted.
- `--vault` — save transcript to `vaults/<vault>/raw/<filename>-transcript.md` with proper frontmatter.
- `--provider` — force a provider: `openai`, `local`. Default: auto-detect (OpenAI if key present, else local).

## Step 1: Dependency Check

```bash
# ffmpeg is required to extract/convert audio
which ffmpeg >/dev/null 2>&1 || {
  echo "Installing ffmpeg…"
  brew install ffmpeg
}

# Determine transcription provider
if [ "$PROVIDER" = "local" ] || [ -z "$OPENAI_API_KEY" ]; then
  # Try local whisper
  if which whisper-cpp >/dev/null 2>&1; then
    TRANSCRIBE_BACKEND="whisper-cpp"
  elif which whisper >/dev/null 2>&1; then
    TRANSCRIBE_BACKEND="whisper-python"
  elif [ -n "$OPENAI_API_KEY" ]; then
    TRANSCRIBE_BACKEND="openai"
  else
    echo "❌ No transcription backend available."
    echo ""
    echo "Options:"
    echo "  1. Set OPENAI_API_KEY for cloud transcription (~\$0.006/min)"
    echo "  2. Install local whisper: brew install whisper-cpp"
    echo "  3. Install Python whisper: pip install openai-whisper"
    exit 1
  fi
else
  TRANSCRIBE_BACKEND="openai"
fi
```

## Step 2: Extract Audio

Convert video to audio, or normalize audio format for Whisper:

```bash
INPUT_FILE="$1"
AUDIO_FILE="/tmp/transcribe-audio-$$.wav"

# Get file info
DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)
HAS_VIDEO=$(ffprobe -v quiet -select_streams v -show_entries stream=codec_type -of csv=p=0 "$INPUT_FILE" 2>/dev/null)

if [ -n "$HAS_VIDEO" ]; then
  echo "Extracting audio from video…"
fi

# Convert to 16kHz mono WAV (Whisper's preferred format)
ffmpeg -i "$INPUT_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_FILE" -y 2>/dev/null
```

## Step 3: Transcribe

### OpenAI Whisper API

```bash
if [ "$TRANSCRIBE_BACKEND" = "openai" ]; then
  # Whisper API has a 25MB file size limit
  FILE_SIZE=$(wc -c < "$AUDIO_FILE" | tr -d ' ')
  
  if [ "$FILE_SIZE" -gt 26214400 ]; then
    # Split into 10-minute chunks
    CHUNK_DIR="/tmp/transcribe-chunks-$$"
    mkdir -p "$CHUNK_DIR"
    ffmpeg -i "$AUDIO_FILE" -f segment -segment_time 600 \
      -c copy "$CHUNK_DIR/chunk_%03d.wav" 2>/dev/null
    
    TRANSCRIPT=""
    for chunk in "$CHUNK_DIR"/chunk_*.wav; do
      CHUNK_RESULT=$(curl -s https://api.openai.com/v1/audio/transcriptions \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -F file=@"$chunk" \
        -F model=whisper-1 \
        -F response_format="${FORMAT:-text}" \
        ${LANGUAGE:+-F language="$LANGUAGE"})
      TRANSCRIPT="$TRANSCRIPT$CHUNK_RESULT\n\n"
    done
    rm -rf "$CHUNK_DIR"
  else
    TRANSCRIPT=$(curl -s https://api.openai.com/v1/audio/transcriptions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -F file=@"$AUDIO_FILE" \
      -F model=whisper-1 \
      -F response_format="${FORMAT:-text}" \
      ${LANGUAGE:+-F language="$LANGUAGE"})
  fi
fi
```

### Local whisper-cpp

```bash
if [ "$TRANSCRIBE_BACKEND" = "whisper-cpp" ]; then
  MODEL_PATH="/usr/local/share/whisper-cpp/models/ggml-base.en.bin"
  [ -f "$MODEL_PATH" ] || MODEL_PATH="$(brew --prefix whisper-cpp 2>/dev/null)/share/whisper-cpp/models/ggml-base.en.bin"
  
  whisper-cpp -m "$MODEL_PATH" \
    -f "$AUDIO_FILE" \
    --output-format txt \
    -of "/tmp/transcribe-result-$$" \
    ${LANGUAGE:+--language "$LANGUAGE"}
  
  TRANSCRIPT=$(cat "/tmp/transcribe-result-$$.txt")
fi
```

### Python whisper

```bash
if [ "$TRANSCRIBE_BACKEND" = "whisper-python" ]; then
  TRANSCRIPT=$(whisper "$AUDIO_FILE" \
    --model base.en \
    --output_format txt \
    --output_dir /tmp \
    ${LANGUAGE:+--language "$LANGUAGE"} 2>/dev/null)
  
  [ -z "$TRANSCRIPT" ] && TRANSCRIPT=$(cat "/tmp/$(basename "$AUDIO_FILE" .wav).txt")
fi
```

## Step 4: Write Output

```bash
OUTPUT="${OUTPUT_PATH:-$(dirname "$INPUT_FILE")/$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')-transcript.md}"

if [ -n "$VAULT_NAME" ]; then
  VAULT_DIR="vaults/$VAULT_NAME"
  SLUG=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
  OUTPUT="$VAULT_DIR/raw/${SLUG}-transcript.md"
  
  cat > "$OUTPUT" <<EOF
---
source-url: "file://$(realpath "$INPUT_FILE")"
title: "$(basename "$INPUT_FILE")"
date-fetched: $(date +%Y-%m-%d)
source-type: $([ -n "$HAS_VIDEO" ] && echo "video" || echo "audio")
transcription-provider: $TRANSCRIBE_BACKEND
duration-seconds: ${DURATION:-unknown}
---

$TRANSCRIPT
EOF
else
  echo "$TRANSCRIPT" > "$OUTPUT"
fi
```

## Step 5: Report

```
✅ Transcription complete
   Input:    <input file> (<duration>s)
   Provider: <openai|whisper-cpp|whisper-python>
   Language: <detected or specified>
   Words:    <word count>
   Output:   <output path>
   Cost:     ~$<estimated> (OpenAI) or free (local)
```

## Test Command

Quick connectivity test to verify the API key works:

```bash
# Test OpenAI Whisper API
curl -s https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = [m['id'] for m in data.get('data', []) if 'whisper' in m['id']]
print('✅ OpenAI API key valid. Whisper models:', ', '.join(models) if models else 'whisper-1 (default)')
" 2>/dev/null || echo "❌ OpenAI API key invalid or network error"
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | no* | — | OpenAI API key for Whisper cloud transcription |

*Not required if local whisper-cpp or whisper-python is installed.

## Cost Estimate

- **OpenAI Whisper API**: $0.006 per minute of audio
- **Local whisper-cpp**: free (uses CPU/GPU, slower)
- **Local whisper-python**: free (requires ~1GB model download)

A 90-minute meeting recording costs ~$0.54 via OpenAI API.

## Integration with Other Skills

- `ingest-video` — uses this as its transcription backend (Tier 1: local, Tier 2: OpenAI)
- `ingest` — could route audio files (`.mp3`, `.wav`, `.m4a`) through this skill
- Meeting notes workflow: record Thursday meetings → `/transcribe recording.mp4 --vault llm-wiki-simplicity-taskforce-partnership` → wiki page

## Known Limitations

- **OpenAI file size limit**: 25MB per request. Files are auto-chunked, but chunk boundaries may split mid-sentence.
- **Local whisper** accuracy is lower than the API, especially for non-English or noisy audio.
- **Speaker diarization** (who said what) is not supported by Whisper. For speaker labels, use AssemblyAI (`ASSEMBLYAI_API_KEY`).
- **Streaming** is not supported — the full file must be uploaded/processed before results are available.

## See Also

- `.claude/skills/ingest-video/SKILL.md` — full video ingestion pipeline that uses this for transcription
- `.claude/skills/generate-podcast/SKILL.md` — produces audio that could be round-trip tested via transcribe
- [OpenAI Whisper API docs](https://platform.openai.com/docs/guides/speech-to-text)
