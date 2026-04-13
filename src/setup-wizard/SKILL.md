---
name: setup-wizard
description: Interactive onboarding wizard for environment setup. Guides through skill installation, IDE integration, MCP servers, and API tokens. Use when user wants to set up, onboard, configure environment, or install tools.
argument-hint: [--tokens | --ide | --mcp | --check]
allowed-tools: Bash(*) Read Write Edit Glob Grep
---

# Setup Wizard

Interactive environment onboarding. Runs all sections by default, or target a specific one with flags.

## Usage

```
/setup-wizard           # Full onboarding (all sections)
/setup-wizard --tokens  # API token setup only
/setup-wizard --ide     # IDE integration only
/setup-wizard --mcp     # MCP server setup only
/setup-wizard --check   # Verify everything works
```

## Sections

Run each section in order (or just the flagged one). Use AskUserQuestion for every choice.

### 1. Skill Installation

Detect what's already installed:
- Check `~/.claude/skills/` and `.claude/skills/` for existing skills
- List what's found vs what's missing

Ask user which install method they prefer:
- **Global** — `npx skills add <org>/<repo>/src/<skill> -g`
- **Project-local** — `npx skills add <org>/<repo>/src/<skill>`
- **Symlink** — `git clone` the repo, then `ln -s <clone>/src/<skill> ~/.claude/skills/<skill>` for each

Run the chosen commands. Verify skills appear in the skill list.

### 2. IDE Integration

Detect the environment:
- Check `$TERM_PROGRAM` — "vscode" means VS Code/Cursor
- Check for `$CURSOR_*` env vars — confirms Cursor
- Check for `.cursor/` directory — Cursor project
- Check for `.vscode/` directory — VS Code project

Based on detection, guide setup:
- **Claude Code**: skills go in `~/.claude/skills/` (global) or `.claude/skills/` (project)
- **Cursor**: rules go in `.cursor/rules/` (project) or `.cursorrules` (legacy)
- **Both**: set up both locations, explain the difference

### 3. MCP Servers

Check current MCP config:
- Read `~/.claude/mcp.json` if it exists
- List configured servers and their status

Suggest useful MCP servers (ask which to install):

| Server | Purpose | Install |
|--------|---------|---------|
| Context7 | Up-to-date library docs | `npx @anthropic-ai/claude-code mcp add context7 -- npx -y @upstash/context7-mcp@latest` |
| Playwright | Browser automation & testing | `npx @anthropic-ai/claude-code mcp add playwright -- npx -y @anthropic-ai/mcp-server-playwright` |
| Fetch | HTTP requests from Claude | `npx @anthropic-ai/claude-code mcp add fetch -- npx -y @anthropic-ai/mcp-server-fetch` |

For each selected server, run the install command and verify it appears in config.

### 4. API Tokens

For each token, walk the user through setup:

| Token | Service | Signup URL | Used By |
|-------|---------|-----------|---------|
| `PERPLEXITY_API_KEY` | Perplexity AI | https://perplexity.ai/settings/api | perplexity-research |
| `OPENAI_API_KEY` | OpenAI | https://platform.openai.com/api-keys | various |
| `GITHUB_TOKEN` | GitHub | `gh auth login` or https://github.com/settings/tokens | GitHub integrations |

For each token:
1. Ask if they want to set it up (skip if not needed)
2. Explain what it's used for
3. Provide the signup URL or CLI shortcut
4. Ask user to paste the token (or run `gh auth login` for GitHub)
5. Verify it works:
   - Perplexity: `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" https://api.perplexity.ai/chat/completions -d '{"model":"sonar","messages":[{"role":"user","content":"test"}]}'`
   - OpenAI: `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" https://api.openai.com/v1/models`
   - GitHub: `gh auth status`
6. Save to the appropriate `.env` file

### 5. Check Mode (`--check`)

Verify all configured services still work:
- Run each verification curl/command from section 4
- Check MCP servers are responding
- Check skills are loadable
- Report pass/fail for each item

## Principles

- Never store tokens in plain text in SKILL.md or committed files
- Always verify a token works before declaring success
- If something fails, explain what went wrong and offer to retry
- Keep output clean — summarize results at the end of each section
