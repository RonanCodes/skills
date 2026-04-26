---
name: abair-irish-api
description: Wrap the abair.ie Irish-language speech stack (Trinity College Dublin) — text-to-speech, speech-to-text, and chat. Four subcommands (tts, stt, chat, launch) over one shared kit (openapi.yaml + scalar.html + bruno/). Use for any Irish (Gaeilge) speech work; sibling to /ro:tts-elevenlabs and /ro:transcribe (neither has real Irish coverage).
user-invocable: true
allowed-tools: Bash(curl *) Bash(jq *) Bash(base64 *) Bash(file *) Bash(ffmpeg *) Bash(which *) Bash(brew *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(wc *) Bash(stat *) Bash(sleep *) Bash(python3 *) Bash(open *) Bash(lsof *) Bash(kill *) Read Write Glob
content-pipeline:
  - pipeline:audio
  - platform:agnostic
  - role:primitive
---

# abair-irish-api — Irish speech stack (TTS + STT + chat)

One skill, three subcommands, wrapping Trinity College Dublin's [ABAIR initiative](https://abair.ie):

| Subcommand | Service | Endpoint | Status |
|---|---|---|---|
| `tts` | ABAIR synthesis | `GET https://synthesis.abair.ie/api/synthesise` | Works |
| `stt` | ABAIR-ÉIST / Fotheidil recognition | `POST https://recognition.abair.ie/v3-5/transcribe` | Works |
| `chat` | COMHRÁ Irish chat | `POST https://abair.ie/api/s2s` | **WAA-protected, server-side calls fail** (documented for completeness) |
| `launch` | Local kit viewer | n/a | Starts a local HTTP server, opens Scalar in the browser, opens Bruno pointed at the kit |

The whole abair.ie speech surface lives in this one kit. Replaces the older split skills `/ro:tts-abair` and `/ro:stt-abair`.

## Usage

```
/ro:abair-irish-api tts    "<irish text>"          [--voice <id|alias>] [--output <path>] [--mp3]
/ro:abair-irish-api tts    --file lines.txt        [--voice <id|alias>] [--out-dir <path>] [--mp3]
/ro:abair-irish-api tts    --from-json <path>      [--output <path>] [--mp3] [--phonemes]   # offline: decode a saved synthesise response, no API call
/ro:abair-irish-api stt    --audio <path>          [--out <path>] [--no-punctuation]
/ro:abair-irish-api stt    --file manifest.json    [--out-dir <path>]
/ro:abair-irish-api chat   "<message>"             # will fail; see § Chat
/ro:abair-irish-api launch [--port 8765] [--no-bruno] [--no-browser] [--stop]
/ro:abair-irish-api --list-voices
```

The first positional arg is always the subcommand (`tts | stt | chat | launch`). Everything after that is subcommand-specific.

## License and ethics

abair.ie is provided by Trinity College Dublin under a **non-commercial research / educational license**. This skill calls the same public endpoints the abair.ie web tools call. Use responsibly:

- Identifies itself in the User-Agent so TCD can see who's using it.
- 1-second sleep between successive calls in batch mode. `--no-rate-limit` only for one-off batches you've cleared with them.
- Cache outputs locally — re-running the same input on the same voice is wasteful.
- For commercial use, contact ABAIR via <https://abair.ie/contact>.

## Subcommand: `tts`

Convert Irish text to speech. Outputs WAV by default, optionally MP3 via ffmpeg.

### Voices

Voice IDs follow the pattern `ga_<DIALECT>_<VOICE>_<ENGINE>`:

| Alias | Voice ID | Voice name | Dialect | Engine | Notes |
|---|---|---|---|---|---|
| `connacht-female-sibeal` (default) | `ga_CO_snc_piper` | Sibéal | Connacht (Connemara) | Piper | Modern neural. Default abair web demo voice. |
| `connacht-female-sibeal-hts` | `ga_CO_snc_exthts` | Sibéal | Connacht | HTS | Same voice, older HTS engine |
| `connacht-male-padraig` | `ga_CO_pmc_exthts` | Pádraig | Connacht | HTS | HTS only |
| `munster-female-neasa` | `ga_MU_nnc_piper` | Neasa | Munster | Piper | Modern neural |
| `munster-female-neasa-hts` | `ga_MU_nnc_exthts` | Neasa | Munster | HTS | |
| `munster-male-colm` | `ga_MU_cmg_piper` | Colm | Munster | Piper | |
| `munster-male-danny` | `ga_MU_dms_piper` | Danny | Munster | Piper | **Heritage voice.** Archived native-speaker recordings; treat with care, may have additional ethical constraints not visible in public terms. |
| `munster-female-fianait-anrinn` | `ga_MU_ar_fnm_piper` | Fianait | Munster (An Rinn sub-dialect) | Piper | Distinct An Rinn flavour (Waterford Gaeltacht) |
| `ulster-female-aine` | `ga_UL_anb_piper` | Áine | Ulster (Donegal) | Piper | Modern neural |
| `ulster-female-aine-hts` | `ga_UL_anb_exthts` | Áine | Ulster | HTS | |
| `ulster-male-donall` | `ga_UL_doc_piper` | Dónall | Ulster | Piper | |

Short aliases like `connacht-female`, `munster-male`, `ulster-female` map to the default Piper voice for that combination (Sibéal, Colm, Áine).

### Resolve voice alias to ID

```bash
case "$VOICE_ARG" in
  # Connacht
  connacht-female|connacht-female-sibeal|sibeal)                VOICE_ID="ga_CO_snc_piper" ;;
  connacht-female-sibeal-hts|sibeal-hts)                        VOICE_ID="ga_CO_snc_exthts" ;;
  connacht-male|connacht-male-padraig|padraig|padraig-hts)      VOICE_ID="ga_CO_pmc_exthts" ;;
  # Munster
  munster-female|munster-female-neasa|neasa)                    VOICE_ID="ga_MU_nnc_piper" ;;
  munster-female-neasa-hts|neasa-hts)                           VOICE_ID="ga_MU_nnc_exthts" ;;
  munster-male|munster-male-colm|colm)                          VOICE_ID="ga_MU_cmg_piper" ;;
  munster-male-danny|danny)                                     VOICE_ID="ga_MU_dms_piper" ;;  # heritage
  munster-female-fianait-anrinn|fianait|an-rinn)                VOICE_ID="ga_MU_ar_fnm_piper" ;;
  # Ulster
  ulster-female|ulster-female-aine|aine)                        VOICE_ID="ga_UL_anb_piper" ;;
  ulster-female-aine-hts|aine-hts)                              VOICE_ID="ga_UL_anb_exthts" ;;
  ulster-male|ulster-male-donall|donall)                        VOICE_ID="ga_UL_doc_piper" ;;
  # Raw ID passthrough
  ga_*)                                                         VOICE_ID="$VOICE_ARG" ;;
  *)
    echo "Unknown voice: $VOICE_ARG" >&2
    echo "Use --list-voices to see all options." >&2
    exit 1
    ;;
esac
```

### Call the synthesis API

```bash
ENCODED=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$INPUT")
URL="https://synthesis.abair.ie/api/synthesise?input=${ENCODED}&voice=${VOICE_ID}&normalise=true"

curl -sS -o /tmp/abair-resp.json -w "%{http_code}" \
  -H 'Accept: */*' \
  -H 'Origin: https://abair.ie' \
  -H 'Referer: https://abair.ie/' \
  -H 'User-Agent: abair-irish-api-skill/1.0 (+https://abair.ie; non-commercial; via /ro:abair-irish-api)' \
  "$URL" > /tmp/abair-status

STATUS=$(cat /tmp/abair-status)
[ "$STATUS" = "200" ] || { echo "abair.ie returned HTTP $STATUS" >&2; cat /tmp/abair-resp.json >&2; exit 1; }

jq -r '.audioContent' /tmp/abair-resp.json | base64 -d > "$OUTPUT"
```

If `--mp3` flag set:

```bash
if [ "$WANT_MP3" = "1" ]; then
  command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found; install with: brew install ffmpeg" >&2; exit 1; }
  MP3_OUT="${OUTPUT%.wav}.mp3"
  ffmpeg -y -i "$OUTPUT" -codec:a libmp3lame -qscale:a 4 "$MP3_OUT" 2>/dev/null
  echo "Wrote $MP3_OUT"
else
  echo "Wrote $OUTPUT"
fi
```

If `--phonemes` flag set, also print the IPA breakdown:

```bash
[ "$SHOW_PHONEMES" = "1" ] && jq -r '.phonemes[]' /tmp/abair-resp.json | sed 's/^/  /'
```

### Offline decode (`tts --from-json`)

For when you already have a saved synthesise response (downloaded from Bruno's response panel, Scalar's Try-It, or a previous `tts` run that saved JSON instead of WAV) and just want to play the audio. Skips the API call entirely.

```bash
if [ -n "$FROM_JSON" ]; then
  [ -f "$FROM_JSON" ] || { echo "JSON not found: $FROM_JSON" >&2; exit 1; }
  jq -e '.audioContent' "$FROM_JSON" >/dev/null 2>&1 || { echo "No audioContent field in $FROM_JSON" >&2; exit 1; }
  OUTPUT="${OUTPUT:-${FROM_JSON%.json}.wav}"
  jq -r '.audioContent' "$FROM_JSON" | base64 -d > "$OUTPUT"
  echo "Wrote $OUTPUT"
  [ "$WANT_MP3" = "1" ] && ffmpeg -y -i "$OUTPUT" -codec:a libmp3lame -qscale:a 4 "${OUTPUT%.wav}.mp3" 2>/dev/null && echo "Wrote ${OUTPUT%.wav}.mp3"
  [ "$SHOW_PHONEMES" = "1" ] && jq -r '.phonemes[]?' "$FROM_JSON" | sed 's/^/  /'
  open "$OUTPUT" 2>/dev/null || true
  exit 0
fi
```

Examples:

```
/ro:abair-irish-api tts --from-json ~/Downloads/response5.json
# → writes ~/Downloads/response5.wav and opens it

/ro:abair-irish-api tts --from-json /tmp/abair-resp.json --output /tmp/foo.wav --mp3 --phonemes
# → also makes foo.mp3 and prints the IPA breakdown
```

### Batch mode (`tts --file`)

Each non-empty line of `lines.txt` becomes a separate synthesis call. Output filenames hash the input + voice so re-runs skip the API call.

```bash
mkdir -p "$OUT_DIR"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  HASH=$(echo -n "${line}|${VOICE_ID}" | shasum -a 256 | cut -c1-8)
  SLUG=$(echo "$line" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-30 | sed 's/-$//')
  OUTPUT="${OUT_DIR}/${SLUG}-${HASH}.wav"
  [ -f "$OUTPUT" ] && { echo "skip (cached): $line"; continue; }
  # ...synthesis call from above...
  sleep "$RATE_LIMIT_SEC"
done < "$INPUT_FILE"
```

## Subcommand: `stt`

Transcribe Irish audio (WAV / WebM / MP3 / Opus) to text via ABAIR-ÉIST / Fotheidil. The **only** option for Irish STT today: OpenAI Whisper does not include `ga` in its tokenizer, ElevenLabs has no Irish, and Web Speech API does not work in installed iOS PWAs.

### Call the transcribe endpoint

```bash
[ -f "$INPUT_AUDIO" ] || { echo "Audio not found: $INPUT_AUDIO" >&2; exit 1; }
MIME=$(file -b --mime-type "$INPUT_AUDIO")

curl -sS -o /tmp/abair-stt-resp.json -w "%{http_code}" \
  -H 'Accept: */*' \
  -H 'Origin: https://abair.ie' \
  -H 'Referer: https://abair.ie/' \
  -H 'User-Agent: abair-irish-api-skill/1.0 (+https://abair.ie; non-commercial; via /ro:abair-irish-api)' \
  -F "file=@${INPUT_AUDIO};type=${MIME}" \
  https://recognition.abair.ie/v3-5/transcribe > /tmp/abair-stt-status

STATUS=$(cat /tmp/abair-stt-status)
[ "$STATUS" = "200" ] || { echo "abair.ie returned HTTP $STATUS" >&2; cat /tmp/abair-stt-resp.json >&2; exit 1; }

cp /tmp/abair-stt-resp.json "$OUTPUT"
TEXT=$(jq -r '.text' "$OUTPUT")
APPLIED=$(jq -r '.captpunct_applied' "$OUTPUT")
echo "$TEXT"
echo "(captpunct_applied: $APPLIED, written to $OUTPUT)"
```

### Batch mode (`stt --file manifest.json`)

Manifest shape:

```json
[
  { "id": "cailleach-greeting", "audio": "assets/audio/ga/cailleach-greeting.wav", "expected": "fáilte go hinis sligigh" },
  { "id": "iasc-win",            "audio": "assets/audio/ga/iasc-win.wav",         "expected": "tá an t-ádh leat" }
]
```

For each entry: transcribe, write `${OUT_DIR}/${id}.json`, optionally compute Levenshtein similarity vs `expected` for cheap pronunciation grading. Sleep 1 second between requests.

### Round-trip sanity check

```bash
/ro:abair-irish-api tts "Failte go hInis Sligigh, a chara!" --output /tmp/test.wav
/ro:abair-irish-api stt --audio /tmp/test.wav
# expected: "fáilte go hinis sligigh a chara"
```

### Pronunciation scoring (cheap version)

```
score = 1 - (levenshtein(normalize(heard), normalize(expected)) / max(len(heard), len(expected)))
```

Threshold of `0.75` works as a "close enough" gate for a kid reading a phrase aloud. For real phoneme-level scoring, only Azure Speech Pronunciation Assessment ships it out of the box (and it has no Irish either). For a love-project, the cheap method is enough.

## Subcommand: `chat`

**This subcommand is documented for completeness but currently does not work server-side.**

The COMHRÁ chat endpoint at `https://abair.ie/api/s2s` is protected by Google's Web App Attestation (WAA / Play Integrity for Web). Requests from anywhere other than a real browser session on `abair.ie` are rejected at the edge before they reach the application. There is no documented bypass; the attestation token is bound to a browser context.

### Endpoint shape (from HAR captures)

```
POST https://abair.ie/api/s2s
Content-Type: application/json

Body:
{
  "messages": [
    { "role": "assistant", "content": "Dia dhuit! Is mise do chomhairleoir Gaeilge. Conas is féidir liom cabhrú leat inniu?" },
    { "role": "user",      "content": "hello" }
  ]
}

Response (200):
{ "text": "Dia dhuit! Conas atá cúrsaí leat?" }
```

The shape is OpenAI-compatible (messages array with role + content). The system prompt is fixed server-side: "speak Irish, gently switch the user back to Irish if they slip into English."

### Why it fails server-side

The skill issues the request, gets back an HTML / JSON challenge from the WAA front, and exits with a clear error. The right pattern for a real chat loop is:

1. **Use this skill's `stt` subcommand** to convert user audio to Irish text.
2. **Call your own LLM** (Claude / Gemini / OpenAI) with a system prompt mirroring COMHRÁ's behaviour.
3. **Use this skill's `tts` subcommand** to speak the LLM's reply.

That gives you a controllable Irish chat loop with no WAA headache, the same TTS quality, and a model you actually pay for / can fine-tune.

If you need the actual COMHRÁ behaviour (fixed Irish-tutor system prompt, abair-controlled model), embed `<https://abair.ie/comhra>` in an iframe — it works in a browser, just not in your server.

### Implementation note

The skill still ships a `chat` subcommand so the surface is discoverable. It posts the request, expects to fail, and reports the WAA failure mode plainly:

```bash
curl -sS -o /tmp/abair-chat-resp.json -w "%{http_code}" \
  -H 'Accept: */*' \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://abair.ie' \
  -H 'Referer: https://abair.ie/comhra' \
  -H 'User-Agent: abair-irish-api-skill/1.0 (+https://abair.ie; non-commercial; via /ro:abair-irish-api)' \
  -d "$(jq -n --arg msg "$INPUT" '{messages:[{role:"user",content:$msg}]}')" \
  https://abair.ie/api/s2s > /tmp/abair-chat-status

STATUS=$(cat /tmp/abair-chat-status)
if [ "$STATUS" != "200" ]; then
  echo "Chat endpoint returned HTTP $STATUS — expected, this endpoint is WAA-protected." >&2
  echo "Use stt + your own LLM + tts instead. See § Chat in SKILL.md." >&2
  exit 2
fi
echo "Unexpectedly worked. Response:" >&2
cat /tmp/abair-chat-resp.json
```

## Subcommand: `launch`

One-shot kit launcher. Starts a local HTTP server in the skill directory, opens the Scalar viewer in the default browser (all three operations visible in the sidebar), and opens Bruno pointed at the `bruno/` collection. Useful when you want to play with the API surface without invoking subcommands one at a time.

```bash
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"   # the abair-irish-api kit dir
PORT="${PORT:-8765}"

# --stop: kill any server already on $PORT and exit
if [ "$STOP" = "1" ]; then
  PIDS=$(lsof -ti:"$PORT" 2>/dev/null || true)
  [ -n "$PIDS" ] && kill -9 $PIDS && echo "Stopped server on :$PORT" || echo "No server on :$PORT"
  exit 0
fi

# Bail early if port already taken (so we don't silently fail)
if lsof -ti:"$PORT" >/dev/null 2>&1; then
  echo "Port $PORT already in use. Run with --stop first, or pass --port <other>." >&2
  exit 1
fi

# Start the server in the background, log to /tmp
( cd "$SKILL_DIR" && python3 -m http.server "$PORT" >/tmp/abair-irish-api-launch.log 2>&1 & )
sleep 1

# Verify it came up
if ! curl -sf -o /dev/null "http://localhost:$PORT/scalar.html"; then
  echo "Server failed to start on :$PORT (see /tmp/abair-irish-api-launch.log)" >&2
  exit 1
fi
echo "Scalar:  http://localhost:$PORT/scalar.html"

# Open the viewers
[ "$NO_BROWSER" = "1" ] || open "http://localhost:$PORT/scalar.html"
[ "$NO_BRUNO"   = "1" ] || open -a Bruno "$SKILL_DIR/bruno/"

cat <<EOM

Bruno is open but does not auto-import the collection. Inside Bruno:
  Collection → Open Collection → $SKILL_DIR/bruno/

To stop the local server later:
  /ro:abair-irish-api launch --stop
EOM
```

Flags:
- `--port <n>` — port for the local HTTP server. Default `8765`.
- `--no-bruno` — skip launching Bruno (just serve Scalar).
- `--no-browser` — skip opening Scalar in the default browser (just start the server).
- `--stop` — kill any server already on `--port` and exit.

The server runs detached. Stop it later with `--stop` or `lsof -ti:8765 | xargs kill -9`.

## When to use this vs other speech skills

- **TTS:** use `abair-irish-api tts` for any Irish text. Use `/ro:tts-elevenlabs` for English NPC dialogue or any non-Irish language. Use OpenAI TTS for cheap single-voice English narration.
- **STT:** use `abair-irish-api stt` for any Irish audio. Use `/ro:transcribe` (Whisper) for English / Dutch / ~98 other languages. Web Speech API in the browser is fine for desktop Chrome but does not work in installed iOS PWAs.
- **Chat:** use `stt` + your own LLM + `tts` (see § Chat). The native COMHRÁ endpoint is browser-only.

For a bilingual game like [llm-wiki/puca-isles](file:///Users/ronan/Dev/ai-projects/puca-isles): every dialogue line is `{en, ga}`. The `en` value goes through `/ro:tts-elevenlabs`, the `ga` value goes through `abair-irish-api tts`. Player-spoken Irish goes through `abair-irish-api stt`.

## Sister files in this kit

- `openapi.yaml` — OpenAPI 3.1 spec covering all three endpoints. Two servers (synthesis + recognition + abair root). Single source of truth for the surface.
- `scalar.html` — open in a browser for interactive docs (loads `openapi.yaml`). Sidebar lists all three operations. Configured with `proxyUrl: https://proxy.scalar.com` so the **Send** button works despite abair.ie's CORS rules; without it, Scalar's API client would either be blocked by CORS or fall back to the page origin (returning a confusing `501` from the local Python server). Requests routed through Scalar's hosted proxy are public — fine for these unauthenticated abair endpoints, do not adopt this config for endpoints carrying secret tokens.
- `bruno/` — [Bruno](https://www.usebruno.com/) collection. `synthesise.bru`, `transcribe.bru`, `chat.bru` (chat documented as expected-to-fail). Open the folder in Bruno via Collection → Open Collection.
- `README.md` — explains how the four pieces fit together.

## Caveats

- All three endpoints are undocumented by ABAIR. Trinity College may change them. If a subcommand stops working, check `https://abair.ie/{synthesis,recognition,comhra}` in a browser, look at the network tab, see if the URL pattern still matches.
- For projects that need a stable Irish API guarantee, contact ABAIR via <https://abair.ie/contact> for institutional partnerships. There is also a gated `api.abair.ie/v4` surface with proper docs and likely an SLA — TCD have not published the path for getting a key.
- TTS output WAV is 22050 Hz 16-bit mono PCM. MP3 conversion via ffmpeg defaults to VBR quality 4 (~128 kbps), fine for game dialogue.
- STT max audio length untested but the page handles dictation of paragraphs comfortably. For very long audio, split client-side and concat transcripts.

## Sources

- [ABAIR initiative homepage](https://abair.ie/)
- [Synthesis tool](https://abair.ie/synthesis) (web demo for `tts`)
- [Recognition tool](https://abair.ie/recognition) (web demo for `stt`)
- [COMHRÁ tool](https://abair.ie/comhra) (web demo for `chat`)
- ABAIR-ÉIST paper (2022): <https://aclanthology.org/2022.cltw-1.7/>
- Fotheidil paper (2025): <https://arxiv.org/html/2501.00509v1>
