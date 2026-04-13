# Skills

Personal agent skills for Claude Code, Cursor, Codex, and [40+ other AI agents](https://agentskills.io).

## Install

### Option 1: npx (one-time install, works with any agent)

Install globally (available in all projects):

```bash
npx skills add RonanCodes/ronan-skills/src/ralph -g
npx skills add RonanCodes/ronan-skills/src/write-a-prd -g
npx skills add RonanCodes/ronan-skills/src/tdd -g
npx skills add RonanCodes/ronan-skills/src/commit -g
npx skills add RonanCodes/ronan-skills/src/close-the-loop -g
npx skills add RonanCodes/ronan-skills/src/debug-escape -g
npx skills add RonanCodes/ronan-skills/src/coding-principles -g
npx skills add RonanCodes/ronan-skills/src/grill-me -g
npx skills add RonanCodes/ronan-skills/src/ubiquitous-language -g
npx skills add RonanCodes/ronan-skills/src/git-guardrails -g
npx skills add RonanCodes/ronan-skills/src/frontend-design -g
npx skills add RonanCodes/ronan-skills/src/browser-dev -g
npx skills add RonanCodes/ronan-skills/src/playwright-check -g
npx skills add RonanCodes/ronan-skills/src/visual-diff -g
npx skills add RonanCodes/ronan-skills/src/firefox-cookies -g
npx skills add RonanCodes/ronan-skills/src/perplexity-research -g
npx skills add RonanCodes/ronan-skills/src/create-skill -g
npx skills add RonanCodes/ronan-skills/src/setup-wizard -g
npx skills add RonanCodes/ronan-skills/src/doc-standards -g
npx skills add RonanCodes/ronan-skills/src/remotion-video -g
```

Or install into the current project only (omit `-g`):

```bash
npx skills add RonanCodes/ronan-skills/src/ralph
```

### Option 2: Clone + symlink (stays up to date)

Clone anywhere, then symlink each skill into `~/.claude/skills/`:

```bash
git clone https://github.com/RonanCodes/ronan-skills.git <your-dev-folder>/ronan-skills

# Development Workflow
ln -s <your-dev-folder>/ronan-skills/src/ralph ~/.claude/skills/ralph
ln -s <your-dev-folder>/ronan-skills/src/write-a-prd ~/.claude/skills/write-a-prd
ln -s <your-dev-folder>/ronan-skills/src/tdd ~/.claude/skills/tdd
ln -s <your-dev-folder>/ronan-skills/src/commit ~/.claude/skills/commit
ln -s <your-dev-folder>/ronan-skills/src/close-the-loop ~/.claude/skills/close-the-loop
ln -s <your-dev-folder>/ronan-skills/src/debug-escape ~/.claude/skills/debug-escape
ln -s <your-dev-folder>/ronan-skills/src/coding-principles ~/.claude/skills/coding-principles

# Quality & Review
ln -s <your-dev-folder>/ronan-skills/src/grill-me ~/.claude/skills/grill-me
ln -s <your-dev-folder>/ronan-skills/src/ubiquitous-language ~/.claude/skills/ubiquitous-language
ln -s <your-dev-folder>/ronan-skills/src/git-guardrails ~/.claude/skills/git-guardrails

# Browser & Visual
ln -s <your-dev-folder>/ronan-skills/src/frontend-design ~/.claude/skills/frontend-design
ln -s <your-dev-folder>/ronan-skills/src/browser-dev ~/.claude/skills/browser-dev
ln -s <your-dev-folder>/ronan-skills/src/playwright-check ~/.claude/skills/playwright-check
ln -s <your-dev-folder>/ronan-skills/src/visual-diff ~/.claude/skills/visual-diff
ln -s <your-dev-folder>/ronan-skills/src/firefox-cookies ~/.claude/skills/firefox-cookies

# Research
ln -s <your-dev-folder>/ronan-skills/src/perplexity-research ~/.claude/skills/perplexity-research

# Project Setup & Tooling
ln -s <your-dev-folder>/ronan-skills/src/create-skill ~/.claude/skills/create-skill
ln -s <your-dev-folder>/ronan-skills/src/setup-wizard ~/.claude/skills/setup-wizard
ln -s <your-dev-folder>/ronan-skills/src/doc-standards ~/.claude/skills/doc-standards

# Video & Media
ln -s <your-dev-folder>/ronan-skills/src/remotion-video ~/.claude/skills/remotion-video
```

Skills available globally. `git pull` to update.

## Skills

### Development Workflow

| Skill | Description | Invocation |
|-------|-------------|------------|
| [ralph](src/ralph) | Autonomous build loop. Picks tasks from `.ralph/prd.json`, implements, validates, commits, and tracks progress. | `/ralph [--plan-only \| --single \| --all]` |
| [write-a-prd](src/write-a-prd) | Generate a PRD through an interactive interview. Quick mode writes prd.json directly, plan mode creates a reviewable plan.md first. | `/write-a-prd [--quick \| --plan] <feature>` |
| [tdd](src/tdd) | Test-driven development with red-green-refactor cycles and vertical slices. | `/tdd <feature-or-story>` |
| [commit](src/commit) | Emoji conventional commit format. Handles staging, message formatting, and timestamp rules. | `/commit [--amend]` |
| [close-the-loop](src/close-the-loop) | Verification loop that ensures work is done -- tests pass, UI works, screenshots match. | `/close-the-loop [--all \| --story <id> \| --url <url>]` |
| [debug-escape](src/debug-escape) | Break out of debugging loops by stepping back and researching. Use when stuck or going in circles. | `/debug-escape [error-message]` |
| [coding-principles](src/coding-principles) | Software design principles -- KISS, SOLID, DRY, tracer bullets. Index loaded, detail files read on demand. | `/coding-principles` |

### Quality & Review

| Skill | Description | Invocation |
|-------|-------------|------------|
| [grill-me](src/grill-me) | Stress-test plans, designs, PRDs, or code by asking relentless probing questions. | `/grill-me [file-or-topic]` |
| [ubiquitous-language](src/ubiquitous-language) | Extract and maintain a DDD-style glossary for consistent domain terminology. | `/ubiquitous-language [--scan \| --check \| --add <term>]` |
| [git-guardrails](src/git-guardrails) | Safety net that blocks destructive git commands and suggests safer alternatives. Background skill for hooks. | _(auto-loaded)_ |

### Browser & Visual

| Skill | Description | Invocation |
|-------|-------------|------------|
| [frontend-design](src/frontend-design) | Create distinctive, production-grade frontend interfaces. Avoids generic AI aesthetics. | `/frontend-design` |
| [browser-dev](src/browser-dev) | Lightweight browser automation via custom scripts. No MCP required, scripts saved for reuse. | `/browser-dev <url> [--screenshot \| --check \| --flow "..."]` |
| [playwright-check](src/playwright-check) | Browser-based verification using Playwright MCP. Navigate, interact, screenshot, check console errors. | `/playwright-check <url> [--flow <steps> \| --responsive]` |
| [visual-diff](src/visual-diff) | Compare two images for visual correctness using pixel diff and Claude vision. | `/visual-diff <image1> <image2> [--threshold 95]` |
| [firefox-cookies](src/firefox-cookies) | Extract cookies from Firefox for authenticated web scraping. macOS only. | _(called by other skills)_ |

### Research

| Skill | Description | Invocation |
|-------|-------------|------------|
| [perplexity-research](src/perplexity-research) | AI-powered web research using the Perplexity API. Returns sourced answers with citations. | `/perplexity-research <query> [--model sonar\|sonar-pro]` |

### Project Setup & Tooling

| Skill | Description | Invocation |
|-------|-------------|------------|
| [create-skill](src/create-skill) | Create a new Claude Code skill with proper SKILL.md structure, frontmatter, and best practices. | `/create-skill [skill-name]` |
| [setup-wizard](src/setup-wizard) | Interactive onboarding wizard for environment setup. Guides through skills, IDE, MCP servers, and API tokens. | `/setup-wizard [--tokens \| --ide \| --mcp \| --check]` |
| [doc-standards](src/doc-standards) | Documentation conventions: mermaid diagrams, formatting, when to use which diagram type. | _(auto-loaded)_ |

### Video & Media

| Skill | Description | Invocation |
|-------|-------------|------------|
| [remotion-video](src/remotion-video) | Generate programmatic videos using Remotion (React to video). Marketing promo and app demo modes. | `/remotion-video [--marketing \| --demo] <project>` |

## Recommended MCPs

These MCP servers pair well with the skills above. Install globally so they're available in every project:

```bash
claude mcp add -s user playwright -- npx @playwright/mcp@latest
claude mcp add -s user context7 -- npx -y @upstash/context7-mcp@latest
```

| MCP | What it does |
|-----|-------------|
| [Playwright](https://github.com/anthropics/mcp-playwright) | Browser automation -- test UIs, take screenshots, interact with web pages |
| [Context7](https://github.com/upstash/context7) | Fetch up-to-date docs for any library directly into context (no API key needed) |

## How It Works

These skills follow the [Agent Skills](https://agentskills.io) open standard. Each skill is a `SKILL.md` file with YAML frontmatter.

```
repo/
├── src/
│   ├── ralph/SKILL.md
│   ├── write-a-prd/SKILL.md
│   ├── tdd/SKILL.md
│   ├── commit/SKILL.md
│   ├── close-the-loop/SKILL.md
│   ├── debug-escape/SKILL.md
│   ├── coding-principles/SKILL.md       + principles/*.md detail files
│   ├── grill-me/SKILL.md
│   ├── ubiquitous-language/SKILL.md
│   ├── git-guardrails/SKILL.md
│   ├── frontend-design/SKILL.md
│   ├── browser-dev/SKILL.md
│   ├── playwright-check/SKILL.md
│   ├── visual-diff/SKILL.md
│   ├── firefox-cookies/SKILL.md
│   ├── perplexity-research/SKILL.md
│   ├── create-skill/SKILL.md
│   ├── setup-wizard/SKILL.md
│   ├── doc-standards/SKILL.md
│   └── remotion-video/SKILL.md
├── README.md
└── LICENSE
```

## License

MIT
