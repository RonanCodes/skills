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

## The brief must be designer-grade, not a screen list

A good Claude Design prompt reads like the brief a senior product designer would demand before touching Figma. A screen-by-screen list is the floor, not the ceiling. The issue this skill emits MUST carry, in order, the seven layers below. Skipping any one of them is the difference between "render me some boxes" and "design my product".

1. **Product context** — one paragraph: what the product is, the core job-to-be-done, why it exists, what makes it different. Pulled from the README / PRD if one exists.
2. **Personas** — 1 to 3 named personas. Each: name + one-line descriptor, their context of use (device, environment, frequency, emotional state), their primary goal, and their top frustration the design must defuse. Personas drive density, tone, affordances, and accessibility. For a personal/single-user app, the persona is still explicit (the one owner), including their constraints (e.g. ADHD: low working memory, decision fatigue, guilt-sensitive).
3. **Art direction / vibe** — the mood in concrete terms, not adjectives alone. Give 3 to 5 mood words AND their cash-out: what they mean for colour temperature, contrast, density, motion, typography character, imagery, and corner/edge treatment. Name what to AVOID (the AI-default aesthetics). Reference 1 to 3 products whose feel is adjacent ("calm like Things 3, dense like Linear, warm like Headspace") so Claude has a north star.
4. **Information architecture** — the full page/surface inventory as a flat list with one-line purpose each, plus the navigation model (how a user moves between them: tab bar, sidebar, command palette, modal stack). This is the map; the per-screen briefs are the territory.
5. **Feature inventory** — the discrete features/capabilities the UI must expose, grouped, so the designer sees the whole surface area, not just the screen they're on. Each feature maps to where it lives in the IA.
6. **Per-screen briefs** — for EACH surface in the IA: goal, layout, content/data shown, audience (which persona), primary + secondary actions, all states (empty / loading / error / success / partial / offline as relevant), key components to reuse, and responsive behaviour (mobile vs desktop). This is the existing four-element brief, expanded.
7. **Key user flows** — 2 to 5 end-to-end journeys stitching screens together ("capture a thought in under 5 seconds from cold open", "morning triage of the inbox", "find a thing I half-remember"). Flows expose transitions, momentum, and the moments that must feel effortless.

Plus two cross-cutting constraints that ride along: **accessibility + responsive** (contrast, focus, hit targets, keyboard, breakpoints, reduced-motion) and **tone / microcopy** (voice of empty states, errors, confirmations — what the product sounds like).

## Steps

### 1. Gather inputs (derive from README/PRD first, ask only for genuine gaps)

Before asking the user anything, **read the repo's README and any PRD / parent issue** (`gh issue view <parent>`, `docs/`, `README.md`). A well-specified product repo already contains personas, features, data model, vibe, and decisions. Mine those first; the seven layers above are usually 80% derivable. Only ask the user for what is genuinely absent or ambiguous (most often: art-direction reference products, and persona emotional context). When running AFK / autonomously, do NOT block on questions: derive the best brief you can from the repo, and explicitly flag any layer you inferred so the human can correct it in Claude Design.

What you need for each of the seven layers:

- **Product context**: the elevator pitch + the core job + the differentiator.
- **Personas**: name, descriptor, device/context/frequency/emotional-state, goal, top frustration. For single-user apps, the one owner, fully drawn.
- **Art direction**: mood words + their cash-out + 1-3 reference products + the AI-default anti-patterns to avoid.
- **Information architecture**: every surface + its purpose + the nav model.
- **Feature inventory**: grouped capabilities mapped to surfaces.
- **Per-screen**: goal, layout, content, audience, primary/secondary actions, full state set, components, responsive.
- **Flows**: the 2-5 journeys that must feel effortless.
- **Stack + repo**: framework (e.g. TanStack Start + shadcn/ui + Tailwind) and the repo URL to link.
- **References**: screenshots / competitor links / decks (optional but valuable).

### 2. Emit the Claude Design prompt

Structure it so it can be pasted straight into a Claude Design project. This is the full designer brief, not a screen list:

```
Project: <name> — high-fidelity prototype. Link repo: <url> (use its existing components + styling).
Stack: <framework + component lib>. Use named components: <Card, Button, Table, ...>.
Design system: inherit org defaults; only deviate where the art direction below says so.
Avoid: generic AI defaults (Inter/Roboto/system fonts, clichéd purple gradients, hero+3-cards, dashboard-template look).

## Product context
<one paragraph: what it is, the core job-to-be-done, the differentiator>

## Personas
Persona 1 — <name>, <one-line descriptor>
  Context: <device / environment / frequency / emotional state>
  Goal: <what they're trying to achieve>
  Frustration to defuse: <the pain the UI must remove>
(repeat for 1-3 personas)

## Art direction / vibe
Mood: <3-5 words>.
  → Colour: <temperature, palette intent, contrast>
  → Density & space: <airy vs dense, where>
  → Motion: <restrained / playful; what animates>
  → Type: <character, not just family — e.g. humanist sans for warmth, mono for IDs>
  → Shape: <corner radius, borders vs shadows, edge treatment>
Feels like: <1-3 reference products and the specific quality borrowed from each>.
Never: <the anti-patterns to avoid, named>.

## Information architecture
- <Surface A> — <purpose>
- <Surface B> — <purpose>
Navigation model: <tab bar / sidebar / command palette / modal stack — how users move>.

## Features
- <group>: <feature> → lives in <surface>
(grouped capability inventory mapped to the IA)

## Screens
Screen 1 — <name> (persona: <which>)
  Goal: <...>
  Layout: <...>
  Content: <data shown>
  Primary actions: <...>   Secondary: <...>
  States: empty / loading / error / success / offline → <each>
  Components: <named components to reuse>
  Responsive: <mobile vs desktop behaviour>
(repeat per surface in the IA)

## Key user flows
1. <flow name>: <screen → screen → screen, and the feeling at each step>
(2-5 flows that must feel effortless)

## Accessibility & responsive
<contrast / focus order / hit targets / keyboard / breakpoints / reduced-motion>

## Tone & microcopy
<voice of empty states, errors, confirmations — what the product sounds like>

Refinement note: use chat for structural changes (palette, layout alternatives), comments (click the element) for component tweaks.
```

Keep one design covering all screens unless they're unrelated. Order screens by the app shell first, then by the primary user flow.

### 3. Emit / update the GitHub design-input issue (agent-native repos)

When this runs for a repo using the Pocock flow, write a **human-checkpoint** issue (NOT `ready-for-agent`, it's a human task). Use the repo's actual human-checkpoint label, which varies: `gh label list` and pick whichever exists, `blocked-on-human` or `needs-human` (the agent-native default in repos like lekkertaal). The issue is *unblocked* (nothing gates it) but it stays a human task, so the human-only label is correct even when no prior issue blocks it.

- Title: `[design-input] <area> — Claude Design brief + links/screenshots (human checkpoint)`
- Body, in this order:
  1. **How to run this** (lead with it): "open a new Claude Design high-fidelity project, link repo `<url>`, copy the prompt block below (Claude Design cannot read this issue), post the share link + one screenshot per screen back here when done."
  2. The **full prompt block** from step 2 (all seven layers + the two cross-cutting constraints), fenced so it copy-pastes clean.
  3. A **"What to paste back"** section: the Claude Design share link (one design is fine) + one screenshot per screen (for the reviewer's visual-diff) + any tokens that deviated from the design system.
  4. An **"Inferred — please sanity-check"** note listing any layer the agent derived rather than was told (so the human corrects it in chat with Claude Design rather than discovering it wrong later).
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
