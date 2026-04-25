---
name: audio-mix
description: Mix multiple audio tracks (voice, music, SFX) into a single output file via ffmpeg. Layer narration over background music, add sound effects at timestamps, adjust volumes.
user-invocable: true
allowed-tools: Bash(ffmpeg *) Bash(ffprobe *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(date *) Bash(cat *) Read Write Glob Grep
content-pipeline:
  - pipeline:audio
  - platform:agnostic
  - role:primitive
---

# Audio Mix

Combine voice, background music, and sound effects into a single mixed audio file using ffmpeg. The glue between `tts-elevenlabs`, `music-elevenlabs`, and `sfx-elevenlabs`.

## Usage

```
/audio-mix --voice narration.mp3 --music background.mp3 [--sfx intro-whoosh.mp3@0s] [--output final.mp3]
/audio-mix --voice narration.mp3 --music bg.mp3 --music-volume 0.15 --sfx click.mp3@5.2s --sfx chime.mp3@30s
```

- `--voice` — primary voice/narration track. Determines the output duration unless `--duration` is set.
- `--music` — background music track. Auto-looped if shorter than voice. Auto-faded out at the end.
- `--sfx <file>@<timestamp>` — sound effect placed at a specific timestamp. Repeatable.
- `--music-volume` — volume level for music (0.0–1.0). Default: `0.15` (subtle background).
- `--sfx-volume` — volume level for SFX (0.0–1.0). Default: `0.6`.
- `--voice-volume` — volume level for voice (0.0–1.0). Default: `1.0`.
- `--fade-in` — fade in duration in seconds for music. Default: `2`.
- `--fade-out` — fade out duration in seconds for music. Default: `3`.
- `--output` — output file path. Default: `/tmp/audio-mix-<timestamp>.mp3`.
- `--duration` — force output duration in seconds. Default: auto from voice track.

## Step 1: Dependency Check

```bash
which ffmpeg >/dev/null 2>&1 || {
  echo "Installing ffmpeg…"
  brew install ffmpeg
}
```

## Step 2: Analyse Input Tracks

```bash
VOICE_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$VOICE_FILE" | cut -d. -f1)
MUSIC_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$MUSIC_FILE" | cut -d. -f1)
OUTPUT_DURATION="${DURATION:-$VOICE_DURATION}"

echo "Voice:    ${VOICE_DURATION}s"
echo "Music:    ${MUSIC_DURATION}s"
echo "Output:   ${OUTPUT_DURATION}s"
echo "SFX cues: ${#SFX_ENTRIES[@]}"
```

## Step 3: Build the ffmpeg Filter Graph

The filter graph layers tracks with volume control, looping, and fading:

```bash
# Base inputs
INPUTS="-i \"$VOICE_FILE\" -i \"$MUSIC_FILE\""
FILTER_PARTS=()
INPUT_IDX=2  # 0=voice, 1=music, 2+=sfx

# Voice: volume adjust
FILTER_PARTS+=("[0:a]volume=${VOICE_VOL:-1.0}[voice]")

# Music: loop if needed, volume, fade in/out
if [ "$MUSIC_DURATION" -lt "$OUTPUT_DURATION" ]; then
  LOOPS=$(( (OUTPUT_DURATION / MUSIC_DURATION) + 1 ))
  FILTER_PARTS+=("[1:a]aloop=loop=${LOOPS}:size=$(( MUSIC_DURATION * 44100 )),atrim=0:${OUTPUT_DURATION},volume=${MUSIC_VOL:-0.15},afade=t=in:d=${FADE_IN:-2},afade=t=out:st=$(( OUTPUT_DURATION - ${FADE_OUT:-3} )):d=${FADE_OUT:-3}[music]")
else
  FILTER_PARTS+=("[1:a]atrim=0:${OUTPUT_DURATION},volume=${MUSIC_VOL:-0.15},afade=t=in:d=${FADE_IN:-2},afade=t=out:st=$(( OUTPUT_DURATION - ${FADE_OUT:-3} )):d=${FADE_OUT:-3}[music]")
fi

# SFX: place each at its timestamp
MIX_INPUTS="[voice][music]"
MIX_COUNT=2

for entry in "${SFX_ENTRIES[@]}"; do
  SFX_FILE="${entry%@*}"
  SFX_TIME="${entry#*@}"
  SFX_TIME="${SFX_TIME%s}"  # strip trailing 's'
  INPUTS+=" -i \"$SFX_FILE\""
  FILTER_PARTS+=("[${INPUT_IDX}:a]volume=${SFX_VOL:-0.6},adelay=${SFX_TIME}s:all=1[sfx${INPUT_IDX}]")
  MIX_INPUTS+="[sfx${INPUT_IDX}]"
  MIX_COUNT=$(( MIX_COUNT + 1 ))
  INPUT_IDX=$(( INPUT_IDX + 1 ))
done

# Final mix
FILTER_PARTS+=("${MIX_INPUTS}amix=inputs=${MIX_COUNT}:duration=first:dropout_transition=0[out]")

FILTER=$(printf "%s;" "${FILTER_PARTS[@]}")
FILTER="${FILTER%;}"  # remove trailing semicolon
```

## Step 4: Render

```bash
OUTPUT="${OUTPUT_PATH:-/tmp/audio-mix-$(date +%s).mp3}"

eval ffmpeg $INPUTS \
  -filter_complex "$FILTER" \
  -map "[out]" \
  -codec:a libmp3lame -qscale:a 2 \
  "$OUTPUT" -y 2>/dev/null
```

## Step 5: Verify & Report

```bash
FINAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$OUTPUT" | cut -d. -f1)
SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
```

```
✅ Audio mixed
   Voice:     <voice file> (<N>s)
   Music:     <music file> (<N>s, vol: <vol>)
   SFX:       <N> cues
   Duration:  <N>s
   Size:      <N> KB
   Output:    <output path>
   Play:      open <output path>
```

## Example: Full Video Audio Track

```bash
# 1. Generate narration
/tts-elevenlabs "Welcome to our product demo..." --output narration.mp3

# 2. Generate background music
/music-elevenlabs "calm modern corporate ambient" --duration 60 --instrumental --output bg-music.mp3

# 3. Generate sound effects
/sfx-elevenlabs "cinematic swoosh transition" --duration 2 --output swoosh.mp3
/sfx-elevenlabs "gentle notification chime" --duration 1 --output chime.mp3

# 4. Mix everything together
/audio-mix \
  --voice narration.mp3 \
  --music bg-music.mp3 --music-volume 0.12 \
  --sfx swoosh.mp3@0s \
  --sfx chime.mp3@15s \
  --sfx chime.mp3@30s \
  --fade-in 3 --fade-out 5 \
  --output final-audio.mp3
```

## Environment Variables

None — this skill uses only ffmpeg (local, free).

## Constraints

- All input files must be decodable by ffmpeg (MP3, WAV, M4A, OGG, FLAC, etc.)
- SFX timestamps must be within the output duration
- Very large numbers of SFX inputs (>20) may hit ffmpeg filter complexity limits

## Integration with Other Skills

- `tts-elevenlabs` — generates the voice track
- `music-elevenlabs` — generates the background music
- `sfx-elevenlabs` — generates individual sound effects
- `generate-video` — uses the mixed audio as the soundtrack for Remotion compositions
- `generate-podcast` — could use this for podcast intros with music + voice

## See Also

- [ffmpeg amix filter](https://ffmpeg.org/ffmpeg-filters.html#amix)
- [ffmpeg adelay filter](https://ffmpeg.org/ffmpeg-filters.html#adelay)
