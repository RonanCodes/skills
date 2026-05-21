---
name: generate-claude-design-prompt
description: Turn a feature or set of screens into a high-quality prompt for Claude Design (claude.ai/design, Anthropic Labs), plus the human-checkpoint GitHub issue that carries it. Use when creating a design-input issue, when the user says "generate a Claude Design prompt", "write a Claude Design brief", "make a design ticket", or when an agent-native flow needs a UI designed before slices can build. Bakes in what Claude Design actually needs (the goal/layout/content/audience brief, repo linking, high-fidelity mode, chat-vs-comments refinement, handoff to Claude Code). Sibling of generate-design-brief (general) and frontend-design.
allowed-tools: Bash Read Glob Grep Write Edit WebFetch
---

# Generate Claude Design Prompt

Produce a prompt that gets buildable, on-brand output from **Claude Design** on the first pass, and the `blocked-on-human` GitHub issue that carries it so a human can run the design and paste the result back. The mirror of a build slice: a slice is "agent builds code"; this is "human runs Claude Design, agent builds against the result."

Claude Design is Anthropic Labs' AI-native design tool (powered by Opus 4.7, research preview; Pro/Max/Team/Enterprise). It turns a prompt into prototypes, slide decks, and one-pagers, refined conversationally, with a handoff bundle straight to Claude Code. Knowing how it ingests context is what separates a vague prompt from a buildable one.

## What Claude Design actually needs (research-backed)

1. **The four-element brief.** Every screen prompt should state: **goal** (what you're building), **layout** (how it's arranged), **content** (what data/information shows), **audience** (who uses it). A four-part brief beats a one-liner every time. "Design a dashboard" → generic; "a single-repo ops dashboard showing PRD progress, open slices grouped by label, and a recent-events feed, for a solo developer running an overnight agent swarm" → specific.
2. **Link the code repo, NOT an issue URL.** Claude Design reads a linked *repository* (components, architecture, styling) to make prototypes production-ready. It does **not** read GitHub issues, so it cannot follow a design-input issue URL. **Consequence:** the design-input issue body must be a **fully self-contained, copy-pasteable prompt** — the human copies the whole block into Claude Design. Never write "paste the issue URL into Claude Design"; write "copy the prompt block below" and "link repo `<url>`".
3. **It inherits the org design system automatically.** Projects pick up the org's brand colours, fonts, and components with no upload. So do NOT re-specify brand basics that already live in the design system; instead **name the components** you want ("use the Card and the Primary Button") because Claude reaches for named components more reliably.
4. **Visual references help.** Screenshots of existing screens, competitor products, or inspiration, and attached decks/docs for a style to replicate.
5. **Mode = High fidelity** for anything a worker will build + the reviewer will visual-diff. Wireframe is only for early layout exploration.
6. **Refinement model:** **chat** for structural changes (colour scheme, rearrange, "show me 2-3 alternative layouts"); **comments** (click the element) for targeted component tweaks; **sliders** Claude generates for spacing/colour/layout. If comments aren't picked up, paste them into chat.
7. **Handoff:** "Send to local coding agent" / "Send to Claude Code Web" exports a handoff bundle. The closed loop is exploration → prototype → production code.

## Anti-patterns to forbid in the prompt

- Generic AI aesthetics: default font families (Inter, Roboto, system), clichéd gradient/colour schemes, predictable hero-then-three-cards layouts. Name a real direction instead.
- Re-specifying brand tokens the design system already owns (wastes the prompt, can fight the system).
- One-sentence prompts. If you can't fill all four brief elements for a screen, gather more first.

## Steps

### 1. Gather inputs (ask if missing, recommend defaults)

- **Screens**: the list of screens/surfaces to design.
- **Per screen**: goal, key content/data shown, primary actions, and states (empty / loading / error).
- **Audience**: who uses it (changes density, tone, affordances).
- **Stack + repo**: the framework (e.g. TanStack Start + shadcn/ui + Tailwind) and the repo URL to link.
- **Visual direction**: rely on the org design system by default; only add direction where the system is silent (e.g. "developer-ops dashboard, information-dense but calm, light + dark, monospace for IDs"). Reuse `frontend-design` / `design-system-create` if a system needs building first.
- **References**: any screenshots/competitor links/decks.

### 2. Emit the Claude Design prompt

Structure it so it can be pasted straight into a Claude Design project:

```
Project: <name> — high-fidelity prototype. Link repo: <url> (use its existing components + styling).
Stack: <framework + component lib>. Use named components: <Card, Button, Table, ...>.
Design system: inherit org defaults; only deviate where noted below.
Avoid: generic AI defaults (Inter/Roboto/system fonts, clichéd gradients, hero+3-cards).

Shared app shell: <nav / top bar / switchers>.

Screen 1 — <name>
  Goal: <...>
  Layout: <...>
  Content: <data shown>
  Audience: <...>
  States: empty / loading / error → <...>

Screen 2 — <name>
  ... (repeat the goal/layout/content/audience/states block)

Refinement note: use chat for structural changes, comments for component tweaks.
```

Keep one design covering all screens unless they're unrelated. Order screens by the app shell first, then by user flow.

### 3. Emit / update the GitHub design-input issue (agent-native repos)

When this runs for a repo using the Pocock flow, write a **human-checkpoint** issue (NOT `ready-for-agent`, it's a human task). Use the repo's actual human-checkpoint label, which varies: `gh label list` and pick whichever exists, `blocked-on-human` or `needs-human` (the agent-native default in repos like lekkertaal). The issue is *unblocked* (nothing gates it) but it stays a human task, so the human-only label is correct even when no prior issue blocks it.

- Title: `[design-input] <area> — Claude Design links + screenshots (human checkpoint)`
- Body: the full prompt from step 2, the per-screen briefs, the stack/visual constraints, and a **"what to paste back"** section: the Claude Design share link (one design is fine) + one screenshot per screen (for the reviewer's visual-diff) + any deviating tokens.
- The UI build slices get `## Blocked by #<this>`; they unblock once the design link lands.

### 4. Report

Hand the user the issue URL and a one-line: "open a new Claude Design **high-fidelity** project, **link the repo** `<url>`, then **copy the prompt block from the issue** (Claude Design can't read the issue itself). Post the share link + one screenshot per screen back when done." The issue body must lead with these copy-paste instructions and contain the entire prompt, so nothing depends on Claude Design reading the issue.

## Relationship to other skills

- `generate-design-brief` — general design brief (any tool/designer); this skill is Claude-Design-specific and emits a paste-ready prompt + issue.
- `frontend-design` / `design-system-create` — build or audit the design system this prompt assumes exists.
- `close-the-loop` — the reviewer side: visual-diff the built UI against the screenshot posted on the design-input issue.

## Sources

- Anthropic: [Introducing Claude Design](https://www.anthropic.com/news/claude-design-anthropic-labs)
- [Get started with Claude Design (Help Center)](https://support.claude.com/en/articles/14604416-get-started-with-claude-design)
- Captured in the llm-wiki ai-research vault: `claude-design` (entity) + `prompting-claude-design` (concept).
