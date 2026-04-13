# Skills

Personal agent skills for Claude Code, Cursor, Codex, and [40+ other AI agents](https://agentskills.io).

## Install

### Option 1: Claude Code Plugin Marketplace (recommended)

```bash
# Add the marketplace (one-time)
/plugin marketplace add RonanCodes/skills

# Install all skills as one plugin
/plugin install ronan-skills@ronan-skills
```

### Option 2: Clone + additionalDirectories

Clone anywhere on your machine:

```bash
git clone https://github.com/RonanCodes/skills.git <your-path>/skills
```

Add to `~/.claude/settings.json`:

```json
{
    "additionalDirectories": ["<your-path>/skills"]
}
```

Update anytime: `cd <your-path>/skills && git pull`

### Option 3: Clone to personal skills

```bash
git clone https://github.com/RonanCodes/skills.git ~/.claude/skills
```

### Option 4: npx (any agent, not just Claude)

```bash
npx skills add RonanCodes/skills/src/ralph -g
npx skills add RonanCodes/skills/src/frontend-design -g
npx skills add RonanCodes/skills/src/create-skill -g
npx skills add RonanCodes/skills/src/doc-standards -g
```


## Skills

| Skill | Description |
|-------|-------------|
| [ralph](/ralph) | Autonomous build loop. Reads PRD, implements one story per iteration, validates, commits, tracks progress. Based on the Ralph Wiggum technique. |
| [frontend-design](/frontend-design) | Create distinctive, production-grade frontend interfaces. Avoids generic AI aesthetics. |
| [create-skill](/create-skill) | Meta-skill for creating new skills with proper SKILL.md structure, frontmatter, and best practices. |
| [doc-standards](/doc-standards) | Documentation conventions: mermaid diagrams, formatting, when to use which diagram type. |

## Auto-register in other projects

To make this marketplace show up automatically when someone opens your project in Claude Code, add this to your project's `.claude/settings.json`:

```json
{
    "extraKnownMarketplaces": {
        "ronan-skills": {
            "source": {
                "source": "github",
                "repo": "RonanCodes/skills"
            }
        }
    }
}
```

Users will see the marketplace in `/plugin` > Discover and can install with one click.

## How It Works

These skills follow the [Agent Skills](https://agentskills.io) open standard. Each skill is a `SKILL.md` file with YAML frontmatter.

The repo supports multiple install methods:

```
repo/
├── src/                              ← SOURCE OF TRUTH
│   ├── ralph/SKILL.md
│   ├── frontend-design/SKILL.md
│   ├── create-skill/SKILL.md
│   └── doc-standards/SKILL.md
├── .claude/skills/                   ← symlinks → src/ (for additionalDirectories)
├── .claude-plugin/marketplace.json   ← marketplace catalog (for Option 1)
├── plugins/ronan-skills/             ← symlinks → src/ (for marketplace plugin)
├── README.md
└── LICENSE
```

## License

MIT
