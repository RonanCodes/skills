---
name: tts-abair
description: Text-to-speech for Irish (Gaeilge) via abair.ie's synthesis API. Outputs WAV (or MP3 with ffmpeg). Three dialects (Connemara, Munster, Ulster), Piper or HTS engines. Use when generating Irish dialogue audio for games or apps. Sibling to /ro:tts-elevenlabs (which has weaker Irish coverage).
user-invocable: true
allowed-tools: Bash(curl *) Bash(jq *) Bash(base64 *) Bash(ffmpeg *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(wc *) Bash(sleep *) Read Write Glob
content-pipeline:
  - pipeline:audio
  - platform:agnostic
  - role:primitive
---

# TTS — abair.ie (Irish / Gaeilge)

Convert Irish text to speech using Trinity College Dublin's [abair.ie](https://abair.ie) synthesis service. Outputs a WAV file by default, optionally converts to MP3 via ffmpeg. Three dialects (Connemara, Munster, Ulster) and two engines (Piper, the modern neural model; HTS, the older statistical model).

## License and ethics

The abair.ie service is provided by Trinity College Dublin's [ABAIR initiative](https://abair.ie/) under a **non-commercial research / educational license**. This skill calls their public synthesis endpoint the same way the abair.ie web tool does. Use responsibly:

- Identifies itself in the User-Agent so they can see who's using it.
- Defaults to a 1-second sleep between successive calls. Use `--no-rate-limit` only for a one-off batch you've cleared with them.
- Cache outputs locally. Re-running the same input on the same voice is wasteful.
- For commercial use, contact ABAIR directly.

## Usage

```
/ro:tts-abair "Failte go hInis Sligigh!" [--voice <id|alias>] [--output <path>] [--mp3]
/ro:tts-abair --file lines.txt [--voice <id|alias>] [--out-dir <path>] [--mp3]
```

Flags:
- `--voice` — Voice ID or alias. Default: `connacht-female` (`ga_CO_snc_piper`).
- `--output` — Output file path. Default: `/tmp/tts-abair-<timestamp>.wav`.
- `--out-dir` — Output directory when `--file` is used; one file per input line, named by hash.
- `--mp3` — Convert WAV to MP3 via ffmpeg (requires ffmpeg on PATH).
- `--phonemes` — Also print the IPA-style phoneme breakdown returned by the API.
- `--list-voices` — Print all known voice IDs and exit.
- `--no-rate-limit` — Skip the 1-second sleep between requests in batch mode. Use with care.

## Voices

Voice IDs follow the pattern `ga_<DIALECT>_<VOICE>_<ENGINE>`:

| Alias | Voice ID | Dialect | Engine | Notes |
|---|---|---|---|---|
| `connacht-female` (default) | `ga_CO_snc_piper` | Connacht (Connemara) | Piper | Sibéal, modern neural voice. The default abair web demo uses this. |
| `connacht-female-hts` | `ga_CO_snc_exthts` | Connacht | HTS | Same voice, older HTS engine |
| `connacht-male-hts` | `ga_CO_pmc_exthts` | Connacht | HTS | Male voice, HTS only |
| `munster-female` | `ga_MU_nnc_piper` | Munster | Piper | Modern neural |
| `munster-female-hts` | `ga_MU_nnc_exthts` | Munster | HTS | |
| `munster-male-1` | `ga_MU_cmg_piper` | Munster | Piper | |
| `munster-male-2` | `ga_MU_dms_piper` | Munster | Piper | |
| `munster-fnm` | `ga_MU_ar_fnm` | Munster | FNM | Older alternate engine |
| `ulster-female` | `ga_UL_anb_piper` | Ulster (Donegal) | Piper | Modern neural |
| `ulster-female-hts` | `ga_UL_anb_exthts` | Ulster | HTS | |
| `ulster-male` | `ga_UL_doc_piper` | Ulster | Piper | |

Pass either the alias (`connacht-female`) or the raw ID (`ga_CO_snc_piper`).

## How it works

The abair.ie synthesis page calls a single endpoint:

```
GET https://synthesis.abair.ie/api/synthesise
    ?input=<URL-encoded Irish text>
    &voice=<voice-id>
    &normalise=true
```

Response is JSON:

```json
{
  "audioContent": "<base64-encoded WAV>",
  "phonemes":     ["1 k o . 0 nn @ s", ...],
  "origins":      ["res/dictionaries/ga_CM/lexicon_conamara.txt++", ...]
}
```

The skill base64-decodes `audioContent` (a 16-bit PCM WAV at 22050 Hz) and writes it to disk. With `--mp3`, it pipes the WAV through ffmpeg to get an MP3 of similar size.

## Step 1: Parse args

Set defaults:
```bash
VOICE_ARG="${VOICE:-connacht-female}"
OUTPUT="${OUTPUT:-/tmp/tts-abair-$(date +%s).wav}"
RATE_LIMIT_SEC=1
```

## Step 2: Resolve voice alias to ID

```bash
case "$VOICE_ARG" in
  connacht-female|sibeal)        VOICE_ID="ga_CO_snc_piper" ;;
  connacht-female-hts)           VOICE_ID="ga_CO_snc_exthts" ;;
  connacht-male-hts)             VOICE_ID="ga_CO_pmc_exthts" ;;
  munster-female)                VOICE_ID="ga_MU_nnc_piper" ;;
  munster-female-hts)            VOICE_ID="ga_MU_nnc_exthts" ;;
  munster-male-1)                VOICE_ID="ga_MU_cmg_piper" ;;
  munster-male-2)                VOICE_ID="ga_MU_dms_piper" ;;
  munster-fnm)                   VOICE_ID="ga_MU_ar_fnm" ;;
  ulster-female)                 VOICE_ID="ga_UL_anb_piper" ;;
  ulster-female-hts)             VOICE_ID="ga_UL_anb_exthts" ;;
  ulster-male)                   VOICE_ID="ga_UL_doc_piper" ;;
  ga_*)                          VOICE_ID="$VOICE_ARG" ;;  # raw ID passthrough
  *)
    echo "Unknown voice: $VOICE_ARG" >&2
    echo "Use --list-voices to see all options." >&2
    exit 1
    ;;
esac
```

## Step 3: Call the synthesis API

```bash
ENCODED=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$INPUT")
URL="https://synthesis.abair.ie/api/synthesise?input=${ENCODED}&voice=${VOICE_ID}&normalise=true"

curl -sS -o /tmp/abair-resp.json -w "%{http_code}" \
  -H 'Accept: */*' \
  -H 'Origin: https://abair.ie' \
  -H 'Referer: https://abair.ie/' \
  -H 'User-Agent: tts-abair-skill/1.0 (+https://abair.ie; non-commercial; via /ro:tts-abair)' \
  "$URL" > /tmp/abair-status

STATUS=$(cat /tmp/abair-status)
if [ "$STATUS" != "200" ]; then
  echo "abair.ie returned HTTP $STATUS" >&2
  cat /tmp/abair-resp.json >&2
  exit 1
fi
```

## Step 4: Decode base64 WAV to file

```bash
jq -r '.audioContent' /tmp/abair-resp.json | base64 -d > "$OUTPUT"
```

If `--mp3` flag set, convert:

```bash
if [ "$WANT_MP3" = "1" ]; then
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found; install with: brew install ffmpeg" >&2
    exit 1
  fi
  MP3_OUT="${OUTPUT%.wav}.mp3"
  ffmpeg -y -i "$OUTPUT" -codec:a libmp3lame -qscale:a 4 "$MP3_OUT" 2>/dev/null
  echo "Wrote $MP3_OUT"
else
  echo "Wrote $OUTPUT"
fi
```

If `--phonemes` flag set, print the IPA breakdown:

```bash
if [ "$SHOW_PHONEMES" = "1" ]; then
  echo "Phonemes:"
  jq -r '.phonemes[]' /tmp/abair-resp.json | sed 's/^/  /'
fi
```

## Step 5: Batch mode (`--file`)

When `--file lines.txt` is passed, each non-empty line becomes a separate synthesis call. Output filenames are derived from a short hash of the input + voice so re-runs of the same line skip the API call.

```bash
mkdir -p "$OUT_DIR"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  HASH=$(echo -n "${line}|${VOICE_ID}" | shasum -a 256 | cut -c1-8)
  SLUG=$(echo "$line" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-30 | sed 's/-$//')
  OUTPUT="${OUT_DIR}/${SLUG}-${HASH}.wav"
  if [ -f "$OUTPUT" ] || ([ "$WANT_MP3" = "1" ] && [ -f "${OUTPUT%.wav}.mp3" ]); then
    echo "skip (cached): $line"
    continue
  fi
  # ...call synthesis as in steps 3-4...
  sleep "$RATE_LIMIT_SEC"  # be polite
done < "$INPUT_FILE"
```

## Example invocations

Single line, default voice:
```
/ro:tts-abair "Failte go hInis Sligigh!"
```

Specific voice + MP3:
```
/ro:tts-abair "Conas atá tú?" --voice ulster-female --mp3 --output ./ulster-greeting.mp3
```

Batch a dialogue file:
```
/ro:tts-abair --file dialogue/cailleach-ban.txt --out-dir assets/audio/ga --mp3
```

List all voices:
```
/ro:tts-abair --list-voices
```

## When to use this vs other TTS

- **Use `/ro:tts-abair`** for any Irish (Gaeilge) text. ABAIR's neural voices are TCD-trained on native speakers across the three dialects and noticeably outperform multilingual TTS models on Irish phonology.
- **Use `/ro:tts-elevenlabs`** for English NPC dialogue, narration, or any non-Irish language. ElevenLabs has 100+ character voices and strong multilingual coverage.
- **Use OpenAI TTS** for cheap single-voice narration. No Irish.

For a bilingual game like [llm-wiki/puca-isles](file:///Users/ronan/Dev/ai-projects/puca-isles): every dialogue line is `{en, ga}`. The `en` value goes through `/ro:tts-elevenlabs`, the `ga` value goes through this skill.

## Caveats

- The endpoint is undocumented. Trinity College may change it. If the skill stops working, check `https://abair.ie/synthesis` in a browser, look at the network tab, see if the URL pattern still matches `/api/synthesise?input=...&voice=...&normalise=true`.
- For projects that need a stable Irish TTS API guarantee, contact ABAIR directly. They have a contact form at <https://abair.ie/contact> for institutional partnerships.
- Quality varies by engine: `_piper` voices are noticeably better than `_exthts` voices on phonology and naturalness. Default to Piper unless the dialect/gender combination only ships HTS.
- Output WAV is 22050 Hz 16-bit mono PCM. MP3 conversion via ffmpeg defaults to VBR quality 4 (~128 kbps), which is fine for game dialogue.

## Sources

- [ABAIR initiative homepage](https://abair.ie/)
- [Synthesis tool](https://abair.ie/synthesis) (the web demo this skill mirrors)
- ABAIR-ÉIST paper (2022): <https://aclanthology.org/2022.cltw-1.7/>
- Fotheidil paper (2025): <https://arxiv.org/html/2501.00509v1>
