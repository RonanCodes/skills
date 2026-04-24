# Git hooks

Versioned hooks live here so they travel with clones. Git does not activate them automatically. Run this once per clone:

```bash
git config core.hooksPath .githooks
```

## Hooks

- **`pre-push`** — auto-bumps `.claude-plugin/plugin.json` version and the skill count in `.claude-plugin/marketplace.json` when `skills/` has changed since the last push. New skill directory → minor bump; existing skill modified → patch bump. Amends the latest commit with the version changes before the push completes.
