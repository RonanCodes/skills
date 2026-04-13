---
name: perplexity-research
description: AI-powered web research using the Perplexity API. Searches the live web and returns sourced answers with citations. Use when user wants to research, look up, search the web, or find current information.
argument-hint: <query> [--model sonar|sonar-pro|sonar-reasoning-pro]
allowed-tools: Bash(curl *) Read Write Edit
---

# Perplexity Research

Search the live web via the Perplexity API. Returns sourced answers with citation URLs.

## Usage

```
/perplexity-research "What are the latest changes in Claude Code?"
/perplexity-research "React Server Components best practices" --model sonar-pro
```

## Models

| Model | Best for |
|-------|----------|
| `sonar` | Quick facts, simple questions (default) |
| `sonar-pro` | Complex multi-step, more citations |
| `sonar-reasoning-pro` | Chain-of-thought, deep analysis |

## Process

### 1. Find API Key

Check these locations in order for `PERPLEXITY_API_KEY`:
1. `.claude/skills/perplexity-research/.env`
2. Project root `.env`
3. `~/.config/perplexity/.env`
4. Environment variable already set

If not found: direct user to https://perplexity.ai/settings/api to create a key (starts with `pplx-`), then save it with `mkdir -p ~/.config/perplexity && echo "PERPLEXITY_API_KEY=pplx-..." > ~/.config/perplexity/.env`. Or run `/setup-wizard --tokens`.

### 2. Call the API

```bash
# Load the key
PERPLEXITY_API_KEY=$(grep PERPLEXITY_API_KEY <env-file> | cut -d= -f2-)

# Make the request
RESPONSE=$(curl -s https://api.perplexity.ai/chat/completions \
  -H "Authorization: Bearer $PERPLEXITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"QUERY\"}]
  }")
```

Default model is `sonar`. Override with `--model` flag or `PERPLEXITY_MODEL` from `.env`.

### 3. Parse and Display

The response is OpenAI-compatible JSON. Answer: `choices[0].message.content`. Citations: `citations` array at root level.

Display as a **Research Results** heading with the answer text, then a **Sources** section with numbered citation URLs. Extract citations: `echo "$RESPONSE" | python3 -c "import sys,json; [print(f'{i+1}. {u}') for i,u in enumerate(json.loads(sys.stdin.read()).get('citations',[]))]"`

### 4. Save Results (optional)

If the user wants to save, write to `research-<slugified-query>.md` with frontmatter (`title`, `date`, `source: perplexity-api`, `model`).

## Error Handling

- **401**: Invalid API key — guide to https://perplexity.ai/settings/api
- **429**: Rate limited — wait and retry
- **Empty response**: Suggest refining the query

## Per-Skill .env

Save at `~/.config/perplexity/.env` (or `.claude/skills/perplexity-research/.env`):

```
PERPLEXITY_API_KEY=pplx-...
PERPLEXITY_MODEL=sonar
```

Never commit API keys.
