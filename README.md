# Skills

Personal agent skills for Claude Code, Cursor, Codex, and [40+ other AI agents](https://agentskills.io).

## Install

### Option 1: npx (one-time install, works with any agent)

Install globally (available in all projects):

```bash
npx skills add RonanCodes/ronan-skills/src/ralph -g
npx skills add RonanCodes/ronan-skills/src/frontend-design -g
npx skills add RonanCodes/ronan-skills/src/create-skill -g
npx skills add RonanCodes/ronan-skills/src/doc-standards -g
npx skills add RonanCodes/ronan-skills/src/commit -g
npx skills add RonanCodes/ronan-skills/src/coding-principles -g
```

Or install into the current project only (omit `-g`):

```bash
npx skills add RonanCodes/ronan-skills/src/ralph
```

### Option 2: Clone + symlink (stays up to date)

Clone anywhere, then symlink each skill into `~/.claude/skills/`:

```bash
git clone https://github.com/RonanCodes/ronan-skills.git <your-dev-folder>/ronan-skills

ln -s <your-dev-folder>/ronan-skills/src/ralph ~/.claude/skills/ralph
ln -s <your-dev-folder>/ronan-skills/src/frontend-design ~/.claude/skills/frontend-design
ln -s <your-dev-folder>/ronan-skills/src/create-skill ~/.claude/skills/create-skill
ln -s <your-dev-folder>/ronan-skills/src/doc-standards ~/.claude/skills/doc-standards
ln -s <your-dev-folder>/ronan-skills/src/commit ~/.claude/skills/commit
ln -s <your-dev-folder>/ronan-skills/src/coding-principles ~/.claude/skills/coding-principles
```

Skills available globally. `git pull` to update.

## Skills

| Skill | Description |
|-------|-------------|
| [ralph](src/ralph) | Autonomous build loop. Reads PRD, implements one story per iteration, validates, commits, tracks progress. Based on the Ralph Wiggum technique. |
| [frontend-design](src/frontend-design) | Create distinctive, production-grade frontend interfaces. Avoids generic AI aesthetics. |
| [create-skill](src/create-skill) | Meta-skill for creating new skills with proper SKILL.md structure, frontmatter, and best practices. |
| [doc-standards](src/doc-standards) | Documentation conventions: mermaid diagrams, formatting, when to use which diagram type. |
| [commit](src/commit) | Emoji conventional commit format. Handles staging, message formatting, and timestamp rules. |
| [coding-principles](src/coding-principles) | Software design principles — KISS, SOLID, DRY, tracer bullets. Index + detail files read on demand. |

## How It Works

These skills follow the [Agent Skills](https://agentskills.io) open standard. Each skill is a `SKILL.md` file with YAML frontmatter.

```
repo/
├── src/                              ← skills (source of truth)
│   ├── ralph/SKILL.md
│   ├── frontend-design/SKILL.md
│   ├── create-skill/SKILL.md
│   ├── doc-standards/SKILL.md
│   ├── commit/SKILL.md
│   └── coding-principles/SKILL.md  ← + principles/*.md detail files
├── README.md
└── LICENSE
```

## License

MIT
