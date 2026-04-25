---
name: video-summarize
description: Ingest a YouTube URL or local video via steipete's `summarize` CLI — returns transcript (with timestamps), scene-detected slides (PNG + optional OCR), and an LLM narrative summary with section headings. Generic sibling to llm-wiki/ingest-youtube and llm-wiki/ingest-video (those persist to a vault; this one just produces artefacts and leaves placement to the caller).
category: research
argument-hint: <youtube-url | local-video-path> [--out <dir>] [--slides-max N] [--length short|medium|long|xl|xxl] [--model <id>] [--ocr] [--skip-summary]
allowed-tools: Bash(summarize *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(source *) Bash(unset *) Read Write
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:primitive
---

# Video Summarize

Thin wrapper around [`summarize`](https://github.com/steipete/summarize) that standardises where the outputs go so callers (like an ingest flow or a research workflow) can consume them.

## What the caller gets

For a single input (YouTube URL or local video file), this skill produces:

1. **`<out>/<slug>-transcript.md`** — full transcript with timestamps, via `summarize --extract --timestamps`
2. **`<out>/<slug>-summary.md`** — narrative summary with section headings, via `summarize --slides --timestamps --length <...>`
3. **`<out>/slides/*.png`** — scene-detected slides, each filename encoding its timestamp (e.g. `slide_0003_96.07s.png`)
4. **`<out>/slides/slides.json`** — machine-readable slide manifest (timestamps, paths, OCR text if enabled)
5. **`<out>/<slug>-summarize-log.txt`** — verbose log from the run (provider used, token counts, cost estimate)

## Usage

```
/ro:video-summarize https://www.youtube.com/watch?v=XXXX                         # defaults: xxl summary, 6 slides
/ro:video-summarize https://www.youtube.com/watch?v=XXXX --out ./my-research     # custom output dir
/ro:video-summarize /path/to/meeting.mp4 --slides-max 20 --ocr                   # local file, more slides, run OCR
/ro:video-summarize https://youtu.be/XXXX --length long --model openai/gpt-4.1   # different length + model
/ro:video-summarize https://youtu.be/XXXX --skip-summary                         # transcript + slides only, no LLM cost
```

## Dependencies

- [`summarize`](https://github.com/steipete/summarize) — `brew install summarize`
- `ffmpeg`, `yt-dlp`, `tesseract` — pulled in automatically by the summarize formula
- **API key** — one of `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY` (or others summarize supports) must be available in the environment. Keys typically live in `~/.claude/.env` (see the user memory on this).

## Process

### 1. Pre-flight

```bash
which summarize >/dev/null 2>&1 || {
  echo "Installing summarize..." >&2
  brew install summarize
}
```

Source API keys from `~/.claude/.env` if present:

```bash
set -a && source ~/.claude/.env && set +a
unset GITHUB_TOKEN GH_TOKEN   # important — see feedback_github_token_env memory
```

### 2. Slug + output dir

Derive a kebab-case slug from the video:
- YouTube URL → use the video title (via `yt-dlp --get-title`) truncated to ~50 chars
- Local file → the filename without extension

Create:

```bash
OUT="${OUT_DIR:-./video-output}"
mkdir -p "$OUT/slides"
```

### 3. Extract transcript (no LLM, fast, free)

```bash
summarize "$INPUT" \
  --extract --timestamps \
  > "$OUT/$SLUG-transcript.md"
```

### 4. Generate summary + slides

```bash
summarize "$INPUT" \
  --slides \
  --slides-dir "$OUT/slides" \
  --slides-max "${SLIDES_MAX:-6}" \
  ${OCR:+--slides-ocr} \
  --timestamps \
  --length "${LENGTH:-xxl}" \
  ${MODEL:+--model "$MODEL"} \
  --verbose \
  > "$OUT/$SLUG-summary.md" \
  2> "$OUT/$SLUG-summarize-log.txt"
```

Skip this step entirely if `--skip-summary`.

### 5. Report back

Print to the caller:
- Where each file landed (absolute paths)
- Slide count + slide timestamps
- Provider used + estimated cost (parse from the last line of the log: `... · $X.XXXX · <model> · ...`)

## Output format (to caller)

```
# Video summarize: <title>  (<duration>)

Transcript:  <abs path>
Summary:     <abs path>
Slides:      <N> slides in <abs path>/slides/
Log:         <abs path>
Cost:        $<X.XXXX> via <model>
```

## Notes

- Summarize caches by URL + flags in `~/.summarize/cache.sqlite`, so re-running is nearly instant and free.
- For meeting-style content where slides matter less, drop `--slides-max` to 3 or use `--skip-summary` and lean on the transcript.
- OCR adds ~100ms per slide; worth it when the video has UI text worth indexing.

## See also

- `llm-wiki/.claude/skills/ingest-youtube` — llm-wiki's transcript-only YouTube handler (no slides). Prefer `/ro:video-summarize` when you need slides/screenshots.
- `llm-wiki/.claude/skills/ingest-video` — llm-wiki's local-video handler (ffmpeg keyframes + whisper transcript, no LLM summary).
- [`steipete/summarize`](https://github.com/steipete/summarize) — the underlying CLI. Source cloned at `~/Dev/.reference/steipete-summarize`.
- `/ro:trend-scan` — upstream: use to find videos worth deep-diving.
