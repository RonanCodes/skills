# abair-irish-api kit

One Claude Code skill, one OpenAPI spec, one Bruno collection, one Scalar viewer — wrapping the entire Trinity College Dublin [ABAIR](https://abair.ie/) Irish-language speech surface.

Replaces the older split skills `tts-abair` and `stt-abair`.

## Three subcommands, three endpoints

| Subcommand | Service | Endpoint | Status |
|---|---|---|---|
| `tts` | ABAIR synthesis | `GET https://synthesis.abair.ie/api/synthesise` | Works |
| `stt` | ABAIR-ÉIST / Fotheidil recognition | `POST https://recognition.abair.ie/v3-5/transcribe` | Works |
| `chat` | COMHRÁ Irish chat | `POST https://abair.ie/api/s2s` | **WAA-protected, server-side calls fail** |

ElevenLabs has limited Irish coverage in their multilingual models; ABAIR's TCD-trained voices are noticeably better for Irish phonology. OpenAI Whisper has no Irish at all. ABAIR is the only viable production option for `ga`.

## What's in here

| File | Purpose |
|---|---|
| `SKILL.md` | The Claude Code slash-command interface (`/ro:abair-irish-api <subcommand>`). Thin wrapper around the curl calls. |
| `openapi.yaml` | OpenAPI 3.1 spec covering all three endpoints. The only formal description that exists; the publisher has none. |
| `scalar.html` | Open in a browser for interactive docs (loads `openapi.yaml`). Sidebar lists all three operations. |
| `bruno/` | [Bruno](https://www.usebruno.com/) collection. `synthesise.bru`, `transcribe.bru`, `chat.bru`. Open the folder in Bruno via Collection → Open Collection. |

## How the four pieces fit together

```
You (in Claude Code)        ──/ro:abair-irish-api tts──▶ SKILL.md (curl GET)
                            ──/ro:abair-irish-api stt──▶ SKILL.md (curl POST multipart)
                            ──/ro:abair-irish-api chat─▶ SKILL.md (expected to 401)

You (in browser)            ──open scalar.html────────▶ interactive contract docs (3 ops)
You (in Bruno)              ──Send button────────────▶ same endpoints, manual smoke tests
Future you / future LLM     ──read openapi.yaml─────▶ understand the surface
```

The OpenAPI spec is the single source of truth. SKILL.md, Scalar, and Bruno are three different lenses on it.

## Quick start

```bash
# TTS — default voice (Connacht / Sibéal / Piper)
/ro:abair-irish-api tts "Failte go hInis Sligigh!"

# TTS — specific voice + MP3 conversion
/ro:abair-irish-api tts "Conas atá tú?" --voice ulster-female --mp3 --output ./greeting.mp3

# TTS — batch from a dialogue file
/ro:abair-irish-api tts --file dialogue/cailleach-ban.txt --out-dir assets/audio/ga --mp3

# STT — transcribe one Irish audio file
/ro:abair-irish-api stt --audio /tmp/recording.wav

# STT — round-trip sanity check
/ro:abair-irish-api tts "Failte go hInis Sligigh, a chara!" --output /tmp/test.wav
/ro:abair-irish-api stt --audio /tmp/test.wav

# Chat — expected to fail (WAA-protected)
/ro:abair-irish-api chat "Dia dhuit"   # exits non-zero with WAA explanation
```

## Browse the spec

```bash
# From the kit directory
python3 -m http.server 8765
open http://localhost:8765/scalar.html
```

## License

Non-commercial / research / educational by default. Identifies itself in `User-Agent`. For commercial use, contact ABAIR via <https://abair.ie/contact>. There is also a gated `api.abair.ie/v4` surface with proper docs and likely an SLA — TCD have not published the path for getting a key, but emailing them is the way in.

## Related skills

- `/ro:tts-elevenlabs` — English (and many other languages) TTS. Use for non-Irish dialogue.
- `/ro:transcribe` — Whisper-based STT. Use for English / Dutch / ~98 other languages. **Has no Irish support.**
