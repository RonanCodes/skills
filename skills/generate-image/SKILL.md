---
name: generate-image
description: Generate images from text prompts via Google Gemini (Nano Banana 2). Outputs PNG files. Use for thumbnails, slide imagery, infographic assets, social cards, or standalone image generation.
user-invocable: true
allowed-tools: Bash(curl *) Bash(which *) Bash(mkdir *) Bash(date *) Bash(cat *) Bash(base64 *) Bash(python3 *) Read Write Glob Grep
---

# Generate Image

Produce images from text prompts using Google Gemini's image generation model (Nano Banana 2). Outputs PNG files to a specified path or to the vault's artifacts directory.

## Usage

```
/generate-image "a flat illustration of an e-commerce dashboard" [--output <path>] [--size <WxH>] [--count <n>]
/generate-image "product comparison infographic" --vault <name> --for <artifact-type>
```

- `--output` — output path. Default: `/tmp/generate-image-<timestamp>.png`.
- `--size` — image dimensions. Default: `1024x1024`. Options: `1024x1024`, `1536x1024` (landscape), `1024x1536` (portrait).
- `--count` — number of images to generate (1-4). Default: 1.
- `--vault` — save output to `vaults/<vault>/artifacts/images/`.
- `--for` — context hint: `thumbnail`, `slide`, `infographic`, `social-card`. Adjusts the system prompt for better results.
- `--style` — style modifier: `flat`, `photorealistic`, `diagram`, `illustration`, `icon`. Default: auto-detected from prompt.

## Step 1: API Key Check

```bash
if [ -z "$GEMINI_API_KEY" ]; then
  echo "❌ GEMINI_API_KEY not set."
  echo ""
  echo "Get your key at: https://aistudio.google.com/apikey"
  echo "Then set it:     export GEMINI_API_KEY=AI..."
  echo "Or add to:       ~/.claude/.env"
  exit 1
fi
```

## Step 2: Build the Prompt

Enhance the user's raw prompt with context based on `--for` and `--style`:

```bash
BASE_PROMPT="$USER_PROMPT"

# Add style context
case "$FOR_CONTEXT" in
  thumbnail)
    SYSTEM_HINT="Create a clean, eye-catching thumbnail image suitable for a video or article card. Bold visuals, minimal text, high contrast."
    ;;
  slide)
    SYSTEM_HINT="Create a presentation slide background or illustration. Clean, professional, with space for overlaid text. Use dark backgrounds (#0f172a) with accent colors (amber #e0af40, cyan #5bbcd6, green #7dcea0)."
    ;;
  infographic)
    SYSTEM_HINT="Create a visual element for an infographic. Flat design, clear iconography, data-visualization style. Use amber (#e0af40), cyan (#5bbcd6), green (#7dcea0) on dark (#0f172a)."
    ;;
  social-card)
    SYSTEM_HINT="Create a social media card image (LinkedIn/Twitter). Professional, branded feel. 1200x630 optimal aspect ratio."
    ;;
  *)
    SYSTEM_HINT=""
    ;;
esac

case "$STYLE" in
  flat)         STYLE_HINT="Flat design style with solid colors and clean shapes." ;;
  photorealistic) STYLE_HINT="Photorealistic style with natural lighting and textures." ;;
  diagram)      STYLE_HINT="Technical diagram style with clean lines and labels." ;;
  illustration) STYLE_HINT="Hand-drawn illustration style with soft lines." ;;
  icon)         STYLE_HINT="Simple icon style, minimal detail, bold shapes." ;;
  *)            STYLE_HINT="" ;;
esac

FULL_PROMPT="$SYSTEM_HINT $STYLE_HINT $BASE_PROMPT"
```

## Step 3: Call the Gemini API

```bash
OUTPUT="${OUTPUT_PATH:-/tmp/generate-image-$(date +%s).png}"
MODEL="gemini-2.0-flash-exp"  # Nano Banana 2 model with image generation

# Gemini image generation via the generateContent endpoint with image output
RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(cat <<PAYLOAD
{
  "contents": [{
    "parts": [{
      "text": "$FULL_PROMPT"
    }]
  }],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  }
}
PAYLOAD
)")

# Extract the base64 image data from the response
IMAGE_DATA=$(echo "$RESPONSE" | python3 -c "
import json, sys, base64
data = json.load(sys.stdin)
parts = data.get('candidates', [{}])[0].get('content', {}).get('parts', [])
for part in parts:
    if 'inlineData' in part:
        print(part['inlineData']['data'])
        break
")

if [ -z "$IMAGE_DATA" ]; then
  echo "❌ Image generation failed. API response:"
  echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
  exit 1
fi

echo "$IMAGE_DATA" | base64 -d > "$OUTPUT"
```

## Step 4: Generate Multiple Images (if --count > 1)

```bash
if [ "$COUNT" -gt 1 ]; then
  BASE="${OUTPUT%.png}"
  mv "$OUTPUT" "${BASE}-1.png"
  for i in $(seq 2 "$COUNT"); do
    # Re-call API with slight prompt variation
    VARIED_PROMPT="$FULL_PROMPT (variation $i of $COUNT, different composition)"
    # ... same API call as Step 3 ...
    echo "$IMAGE_DATA" | base64 -d > "${BASE}-${i}.png"
  done
fi
```

## Step 5: Save to Vault (if --vault)

```bash
if [ -n "$VAULT_NAME" ]; then
  VAULT_DIR="vaults/$VAULT_NAME"
  IMG_DIR="$VAULT_DIR/artifacts/images"
  mkdir -p "$IMG_DIR"
  
  SLUG=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-50)
  DATE=$(date +%Y-%m-%d)
  DEST="$IMG_DIR/${SLUG}-${DATE}.png"
  cp "$OUTPUT" "$DEST"
  
  # Write sidecar
  cat > "${DEST%.png}.meta.yaml" <<EOF
generator: generate-image@0.1.0
generated-at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
model: $MODEL
prompt: "$USER_PROMPT"
style: ${STYLE:-auto}
for: ${FOR_CONTEXT:-standalone}
size: ${SIZE:-1024x1024}
EOF
  
  OUTPUT="$DEST"
fi
```

## Step 6: Report

```
✅ Image generated
   Prompt:  <first 80 chars of prompt>...
   Model:   gemini-2.0-flash-exp (Nano Banana 2)
   Size:    <WxH>
   Style:   <style>
   Output:  <output path>
   Open:    open <output path>
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GEMINI_API_KEY` | yes | — | API key from aistudio.google.com/apikey |

## Cost Estimate

Gemini image generation pricing (as of 2026):
- Free tier: 15 requests/minute, rate limited
- Pay-as-you-go: varies by model — check Google's current pricing

## Observatory Theme Integration

When `--for slide`, `--for infographic`, or `--for social-card` is used, the prompt automatically includes the Observatory palette:
- Amber `#e0af40` — for headings and highlights
- Cyan `#5bbcd6` — for engine/process elements
- Green `#7dcea0` — for outputs and positive indicators
- Dark background `#0f172a`

This keeps generated images visually consistent with other artifacts.

## Integration with Other Skills

- `generate-slides` — can call this to generate slide background images
- `generate-infographic` — can use generated images as visual elements in SVG infographics
- `generate-video` — thumbnail generation for video artifacts
- Portal cards — social card images for sharing artifact links

## Known Limitations

- **Prompt quality matters.** Gemini's image generation is prompt-sensitive. Be specific about composition, style, and colors.
- **No image editing.** This is generation only — no inpainting, outpainting, or variation-from-image (yet).
- **Text in images** is unreliable — Gemini (like most models) struggles with rendering text accurately in images.
- **Rate limits** on the free tier can be restrictive for batch generation.
- **Model ID may change** as Google updates the Nano Banana line. Check Gemini API docs for the latest model supporting image generation.

## See Also

- `.claude/skills/generate-infographic/SKILL.md` — SVG infographic that could use generated images
- `.claude/skills/generate-slides/SKILL.md` — slide deck that could use background images
- [Gemini API image generation docs](https://ai.google.dev/gemini-api/docs/image-generation)
