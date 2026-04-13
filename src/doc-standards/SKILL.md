---
name: doc-standards
description: Documentation standards for the LLM Wiki project. Reference skill loaded when creating or updating markdown docs. Ensures consistent structure, mermaid diagrams, and formatting.
user-invocable: false
---

# Documentation Standards

Reference skill for creating and updating docs in the llm-wiki project. Claude should follow these conventions when writing any `.md` file in `docs/`.

## Structure

Every doc should have:

1. **Title** — `# Clear Title`
2. **Mermaid diagram** — right after the title or first section. Visualize the flow, architecture, or relationship being documented.
3. **Content** — organized with `##` sections
4. **Links** — reference other docs and skills where relevant

## Mermaid Diagram Rules

**Every doc that describes a flow, process, or architecture MUST include at least one mermaid diagram.**

### When to use which diagram type:

| Content | Diagram type | Example |
|---------|-------------|---------|
| Process flow (step by step) | `graph TD` (top-down) | Ingest pipeline, Ralph loop |
| Data flow (A sends to B) | `graph LR` (left-right) | Sources → Engine → Vault → Obsidian |
| Architecture layers | `graph TB` (top-bottom) | Three-layer pattern |
| Timeline / phases | `graph LR` with subgraphs | Roadmap phases |
| Comparisons | Tables (not mermaid) | RAG vs Wiki |
| Decision trees | `graph TD` with diamonds | Vault-create interview |

### Color conventions (Observatory theme):

```
Amber (#e0af40) — user actions, sources, starting points
Cyan (#5bbcd6)  — Claude/engine actions, skills, commands
Green (#7dcea0) — outputs, results, Obsidian, success states
Rose (#d4726a)  — warnings, errors, required items
Grey (#94a3b8)  — future/planned items
```

Apply with: `style NodeName fill:#e0af40,color:#000`

### Diagram style:

- Keep diagrams focused — one concept per diagram, not everything in one
- Use `subgraph` to group related nodes
- Label edges when the relationship isn't obvious
- Use `-.->` for optional/conditional flows, `-->` for required flows
- Short node labels — details go in the surrounding text

## Formatting

- **Tables** for structured comparisons, feature lists, command references
- **Code blocks** with language tag for commands (`bash`), configs (`yaml`, `json`)
- **Bold** for key terms on first mention
- **Links** to other docs: `[doc name](other-doc.md)`
- **No emojis** in docs (unless the user requests them)

## Docs that DON'T need diagrams

- `dataview-queries.md` — code examples are the content
- `dependencies.md` — tables are sufficient
- `decisions.md` — prose reasoning is the content
- `karpathy-research.md` — reference/quote compilation
