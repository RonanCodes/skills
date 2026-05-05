# Ronan Skills (`ro`)

A Claude Code plugin bundling 29 personal skills for development, quality, browser/visual, audio/media, research, and project setup. Invoke any skill as `/ro:<skill-name>`.

Also publishable to Cursor, and individual skills work with [40+ other AI agents](https://agentskills.io) via `npx skills add`.

## Install

### Claude Code (recommended — bundles all 29 skills in one command)

```bash
/plugin marketplace add RonanCodes/ronan-skills
/plugin install ro@ronan-skills
```

Skills then appear as `/ro:ralph`, `/ro:commit`, `/ro:tdd`, etc. Run `/plugin` to manage.

### Cursor

The same repo is also a Cursor plugin (see `.cursor-plugin/plugin.json`). Submit via [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish) or point Cursor at the `skills/` directory locally. Cursor CLI does not yet support plugins — IDE only.

### Other agents (Codex, Cline, etc.) — per-skill install

```bash
npx skills add RonanCodes/ronan-skills/skills/ralph -g
npx skills add RonanCodes/ronan-skills/skills/commit -g
# ...etc per skill, -g for global, omit for project-local
```

## Configuration

Skills that need API keys read from a shared env file via the `ro` meta-CLI (`bin/ro`, symlinked to `~/.local/bin/ro`).

### Single context (most users)

```bash
~/.claude/.env.personal       # all your credentials (mode 600)
~/.claude/.env                # symlink to .env.personal
```

Skills source via `$(ro context env)` which resolves to `~/.claude/.env.personal` automatically. See `.env.example` for every variable, where to generate it, and which skill consumes it. First-time setup:

```bash
ro context init               # creates the template + symlink
# then edit ~/.claude/.env.personal and fill in your keys
# or: /ro:setup-wizard --tokens for a guided walkthrough
```

### Multiple contexts (work / personal / per-client)

If you have separate credentials per project (e.g. a personal Cloudflare account + a client's Cloudflare account), `ro` switches between them with a three-tier resolver:

1. `$RO_CONTEXT` env var — one-shot override per shell
2. `~/.claude/contexts.json:active` — manual override set by `ro context use <name>`
3. `.ro-context.local` in cwd or any ancestor — gitignored contributor override
4. `.ro-context` in cwd or any ancestor — committed, repo's declared context **(cleanest)**
5. cwd-glob rule in `~/.claude/contexts.json` — e.g. `~/Github-Acme/**` → `acme`
6. `default` in `~/.claude/contexts.json`

```bash
# Add another context
cp ~/.claude/.env.personal ~/.claude/.env.acme
# …edit with the client's credentials…

# Pin a repo to its context (preferred — committed, no global config needed)
echo acme > /path/to/repo/.ro-context

# Or auto-resolve via cwd-globs
ro context add-rule '~/Github-Acme/**' acme

# See what resolves and why
ro context where         # context = acme   (resolved from: .ro-context (...))
ro context env           # /Users/you/.claude/.env.acme

# Manual override (sticks until cleared)
ro context use acme
ro context auto          # back to cwd-resolution
```

Backwards compat: skills that haven't migrated to `$(ro context env)` keep working via the `~/.claude/.env` symlink, which `ro context use` updates.

## Skills

All skills invoke as `/ro:<skill-name>` in Claude Code.

### Development Workflow

| Skill | Description |
|-------|-------------|
| [ralph](skills/ralph) | Autonomous build loop. Picks tasks from `.ralph/prd.json`, implements, validates, commits. |
| [write-a-prd](skills/write-a-prd) | Generate a PRD through an interactive interview. Quick or plan mode. |
| [tdd](skills/tdd) | Test-driven development with red-green-refactor cycles and vertical slices. |
| [commit](skills/commit) | Emoji conventional commit format. Handles staging, messages, timestamp rules. |
| [close-the-loop](skills/close-the-loop) | Verification loop — tests pass, UI works, screenshots match. |
| [debug-escape](skills/debug-escape) | Break out of debugging loops by stepping back and researching. |
| [post-mortem](skills/post-mortem) | Document a resolved bug as a structured post-mortem. |
| [coding-principles](skills/coding-principles) | KISS, SOLID, DRY, tracer bullets. Index always loaded, detail files on demand. |

### Quality & Review

| Skill | Description |
|-------|-------------|
| [grill-me](skills/grill-me) | Stress-test plans, designs, PRDs, or code with relentless probing questions. |
| [ubiquitous-language](skills/ubiquitous-language) | DDD-style glossary for consistent domain terminology. |
| [git-guardrails](skills/git-guardrails) | Blocks destructive git commands, suggests safer alternatives. _(auto-loaded)_ |
| [security-audit](skills/security-audit) | Pre-publish safety check — secrets, PII, work info, risky git history. |

### Browser & Visual

| Skill | Description |
|-------|-------------|
| [frontend-design](skills/frontend-design) | Distinctive, production-grade frontend interfaces. Avoids generic AI aesthetics. |
| [browser-dev](skills/browser-dev) | Lightweight browser automation via custom scripts. No MCP required. |
| [playwright-check](skills/playwright-check) | Playwright MCP — navigate, interact, screenshot, check console errors. |
| [visual-diff](skills/visual-diff) | Compare two images using pixel diff and Claude vision. |
| [firefox-cookies](skills/firefox-cookies) | Extract cookies from Firefox for authenticated scraping. macOS only. _(internal)_ |

### Research

| Skill | Description |
|-------|-------------|
| [perplexity-research](skills/perplexity-research) | Sourced web research via the Perplexity API. |

### Audio & Media

| Skill | Description |
|-------|-------------|
| [tts-elevenlabs](skills/tts-elevenlabs) | Text-to-speech via ElevenLabs API. Multiple voices, multilingual. |
| [sfx-elevenlabs](skills/sfx-elevenlabs) | Sound effects generation via ElevenLabs. Text-to-sound, 0.5–30s. |
| [music-elevenlabs](skills/music-elevenlabs) | Music generation via ElevenLabs. Instrumental, composition plans. |
| [audio-mix](skills/audio-mix) | Combine voice + music + SFX via ffmpeg. Volume, fade, timestamps. |
| [generate-image](skills/generate-image) | Image generation via AI APIs. |
| [transcribe](skills/transcribe) | Audio/video transcription to text. |

### Project Setup & Tooling

| Skill | Description |
|-------|-------------|
| [create-skill](skills/create-skill) | Scaffold a new `SKILL.md` with proper structure and frontmatter. |
| [setup-wizard](skills/setup-wizard) | Interactive onboarding — plugin install, IDE, MCP servers, API tokens. |
| [doc-standards](skills/doc-standards) | Documentation conventions — mermaid diagrams, formatting. _(auto-loaded)_ |

## Recommended MCPs

Skills pair well with these MCP servers. Install globally:

```bash
claude mcp add -s user playwright -- npx @playwright/mcp@latest
claude mcp add -s user context7 -- npx -y @upstash/context7-mcp@latest
```

| MCP | What it does |
|-----|-------------|
| [Playwright](https://github.com/microsoft/playwright-mcp) | Browser automation — test UIs, screenshot, interact with pages |
| [Context7](https://github.com/upstash/context7) | Up-to-date library docs in context (no API key needed) |

## Repo Structure

```
ronan-skills/
├── .claude-plugin/
│   ├── plugin.json          # Claude Code plugin manifest (name: "ro")
│   └── marketplace.json     # Marketplace entry
├── .cursor-plugin/
│   └── plugin.json          # Cursor plugin manifest
├── skills/
│   ├── ralph/SKILL.md
│   ├── write-a-prd/SKILL.md
│   ├── tdd/SKILL.md
│   ├── commit/SKILL.md
│   ├── close-the-loop/SKILL.md
│   ├── debug-escape/SKILL.md
│   ├── post-mortem/SKILL.md
│   ├── coding-principles/SKILL.md
│   ├── grill-me/SKILL.md
│   ├── ubiquitous-language/SKILL.md
│   ├── git-guardrails/SKILL.md
│   ├── security-audit/SKILL.md
│   ├── frontend-design/SKILL.md
│   ├── browser-dev/SKILL.md
│   ├── playwright-check/SKILL.md
│   ├── visual-diff/SKILL.md
│   ├── firefox-cookies/SKILL.md
│   ├── perplexity-research/SKILL.md
│   ├── create-skill/SKILL.md
│   ├── setup-wizard/SKILL.md
│   ├── doc-standards/SKILL.md
│   ├── tts-elevenlabs/SKILL.md
│   ├── sfx-elevenlabs/SKILL.md
│   ├── music-elevenlabs/SKILL.md
│   ├── audio-mix/SKILL.md
│   ├── generate-image/SKILL.md
│   └── transcribe/SKILL.md
├── .env.example
├── README.md
└── LICENSE
```

Each skill is a `SKILL.md` with YAML frontmatter (`name`, `description`, `category`, ...). Follows the [Agent Skills](https://agentskills.io) open standard.

## Versioning & Plugin Updates

**Important:** Claude Code's plugin system caches plugins by version. `claude plugin update` and `autoUpdate` both compare the `version` field in `.claude-plugin/plugin.json` — if it hasn't changed, updates silently no-op even if new skills were added.

**Convention:** Bump the version in `.claude-plugin/plugin.json` whenever skills are added, removed, or significantly changed. Use semver:
- **Patch** (1.1.1 → 1.1.2): Fixes within existing skills
- **Minor** (1.1.0 → 1.2.0): New skills added
- **Major** (1.0.0 → 2.0.0): Breaking changes to existing skills

Without a version bump, colleagues running `claude plugin update ro@ronan-skills` will miss new skills.

## License

MIT
