---
name: design-system-create
description: Scaffold a design system in a React/Tailwind project — DESIGN_SYSTEM.md spec + typed tokens module + cva variants for core primitives (Button, Input, Card). Use when a project has hand-rolled Tailwind for buttons/inputs/cards and needs a single source of truth. Pairs with /ro:design-system-audit for enforcement.
category: frontend
argument-hint: [--primitives=button,input,card] [--typescript|--js]
---

# Design System — Create

Lay down the four-layer contract that makes UI predictable:

1. **CSS custom properties** per theme — colour values live here, nowhere else
2. **Tailwind `@theme inline` bridge** — maps vars to utilities (`bg-background` etc.)
3. **Typed tokens module** (`src/design-system/tokens.ts`) — TYPOGRAPHY, SPACING, RADIUS, ELEVATION, Z
4. **`cva`-based component variants** — Button, Input, Card with state tables baked in
5. **`DESIGN_SYSTEM.md`** at repo root — rules, state tables, review checklist

The skill generates these in that order, and leaves the project with zero hex values in component files.

## Usage

```
/ro:design-system-create                          # interactive — inspect repo, propose layout
/ro:design-system-create --primitives=button,input,card
/ro:design-system-create --dry-run                # show what would be written, don't write
```

## Process

### 1. Inspect the project

Run in parallel:

- `ls src/components/ui/` (shadcn layout) or `ls src/components/` (alternative)
- `cat tailwind.config.* 2>/dev/null || cat src/styles.css | head -40`
- `grep -rn '#[0-9a-fA-F]\{3,8\}' src/components/ 2>/dev/null | head -20` (hex leakage)
- `grep -rn 'scale-\|rounded-\[' src/components/ 2>/dev/null | head -20` (likely DS violations)

Determine:
- **Stack**: Tailwind v3 vs v4, shadcn-ui vs custom, cva present or not, TypeScript vs JS
- **Existing primitives**: what Button/Input/Card already exists — augment, don't duplicate
- **Themes**: does the project have multiple themes? where do vars live?

If the project already has some of this (e.g. shadcn-ui scaffolded), the skill augments rather than overwriting. Never clobber an existing `DESIGN_SYSTEM.md` without asking.

### 2. Ask the user

Via `AskUserQuestion`, confirm:

1. **Radius scale** — what rounded-* bracket matches their brand? (default: sm/md/lg/xl/full, md = default)
2. **Primary button shape** — square rounded-md, or pill rounded-full?
3. **Elevation style** — border-only (NYT/modern flat), or borders + shadows (material)?
4. **Active-state feedback** — `translate-y-px` + darker bg (recommended), or fade only?
5. **Primitives to generate** — Button, Input, Card, Badge, Dialog (default: Button + Input + Card)

### 3. Write the CSS layer

If Tailwind v4, ensure `src/styles.css` has:

```css
@import 'tailwindcss';

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-destructive: var(--destructive);
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);

  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);
}
```

The vars themselves live per-theme in `src/lib/themes/css/*.css` (or wherever the project keeps them). Do not inline concrete colours here.

### 4. Write `src/design-system/tokens.ts`

Typed, importable, autocomplete-friendly. Template:

```ts
export const TYPOGRAPHY = {
  display: 'text-3xl md:text-4xl font-bold tracking-tight',
  h1: 'text-2xl md:text-3xl font-bold tracking-tight',
  h2: 'text-xl font-semibold',
  h3: 'text-base font-semibold',
  body: 'text-sm leading-relaxed',
  bodyLg: 'text-base leading-relaxed',
  caption: 'text-xs text-muted-foreground',
  label: 'text-sm font-medium',
  mono: 'font-mono text-xs',
} as const
export type TypographyToken = keyof typeof TYPOGRAPHY

export const SPACING = {
  xs: '1', sm: '2', md: '3', lg: '4', xl: '6', xxl: '8',
} as const
export type SpacingToken = keyof typeof SPACING

export const RADIUS = {
  none: 'rounded-none',
  sm: 'rounded-sm',
  md: 'rounded-md',
  lg: 'rounded-lg',
  xl: 'rounded-xl',
  pill: 'rounded-full',
} as const

export const ELEVATION = {
  flat: 'border border-border',
  raised: 'border border-border shadow-sm',
  floating: 'border border-border shadow-md',
  overlay: 'border border-border shadow-xl',
} as const

export const Z = {
  base: 0, dropdown: 40, overlay: 50, dialog: 60, toast: 70, tooltip: 80,
} as const
```

### 5. Write / augment the primitives

Each primitive follows the same state-table contract. Example for Button:

```tsx
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium " +
  "transition-all duration-150 disabled:pointer-events-none disabled:opacity-50 " +
  "outline-none focus-visible:ring-ring/50 focus-visible:ring-[3px] active:translate-y-px",
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground hover:bg-primary/90 active:bg-primary/80',
        destructive: 'bg-destructive text-white hover:bg-destructive/90 active:bg-destructive/80',
        outline: 'border bg-background hover:bg-accent hover:text-accent-foreground active:bg-accent/80',
        secondary: 'bg-secondary text-secondary-foreground hover:bg-secondary/80 active:bg-secondary/70',
        ghost: 'hover:bg-accent hover:text-accent-foreground active:bg-accent/80',
        link: 'text-primary underline-offset-4 hover:underline active:text-primary/80',
      },
      size: {
        default: 'h-9 px-4 py-2',
        xs: 'h-6 gap-1 px-2 text-xs',
        sm: 'h-8 gap-1.5 px-3',
        lg: 'h-10 px-6',
        icon: 'size-9',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  },
)
```

**Invariants the generated variants enforce:**
- Radius in the base class only — never per-variant, never per-state
- Every variant defines hover + active + (via base) disabled + focus
- Active is momentary: bg darkens, `translate-y-px` — never scales up
- Focus ring is the same everywhere

Mirror this for `Input` (hover border-foreground/30, focus-visible border-ring + ring, disabled opacity-50) and `Card` (Flat/Raised/Floating/Overlay elevation tiers).

### 6. Write `DESIGN_SYSTEM.md`

Root of the repo. Must include:

1. **Source of truth table** — where colours/tokens/variants live, and the change flow
2. **Core rules** — the six non-negotiable rules from the canonical spec (see below)
3. **Per-primitive sections** — variant → intent mapping + state table + sizing
4. **Typography + Spacing** — token names and when to use them
5. **Interaction patterns** — Toggle vs Active (critical, often confused)
6. **Review checklist** — the one-page list reviewers scan
7. **When to deviate** — the escape hatch with guardrails

The six core rules (lift verbatim unless the project has a well-reasoned deviation):

1. Radius is a property of the element, not the state. A button's `rounded-md` must be identical in rest, hover, active, focus, disabled.
2. Active means pressed, not emphasised. The active state is the momentary look during mouse-down: subtly darker or inset. Never use `scale-110` or a larger ring for active — that says "emphasised", which is a different concept (toggle).
3. Every variant must define rest + hover + active + focus-visible + disabled. Missing a state = dead feel in that state.
4. Focus ring is always the same. 3px, `ring-ring/50`, outline-none. Don't customise per variant.
5. Colour comes from tokens, never from hex. If you need a colour the theme doesn't have, add a token; don't inline.
6. One radius scale. `rounded-sm` (badges), `rounded-md` (buttons/inputs), `rounded-lg`/`xl` (cards), `rounded-full` (pills). No `rounded-[7px]` one-offs.

### 7. Report

Print what was written:

```
✅ Design system scaffolded

Created:
  DESIGN_SYSTEM.md                    — spec + review checklist
  src/design-system/tokens.ts         — typed tokens
  src/styles.css                      — @theme inline bridge (augmented)
  src/components/ui/button.tsx        — cva variants with state table
  src/components/ui/input.tsx         — matches button state treatment
  src/components/ui/card.tsx          — elevation tiers

Next:
  1. Run /ro:design-system-audit to find callers that need migrating
  2. Review DESIGN_SYSTEM.md — deviate where your brand demands it
  3. Commit the scaffold before starting migrations
```

## Design decisions this skill bakes in

- **Hybrid doc + code** over JSON-only (Style Dictionary, DTCG) — for solo projects, Style Dictionary's ceremony isn't worth the price. The typed tokens module gives autocomplete without the build step.
- **cva for variants** over inline conditionals — it forces you to name the state table, and class ordering stays stable.
- **`@theme inline` bridge** for Tailwind v4 — maps a small number of semantic vars to a much larger utility surface for free.
- **Rules, not laws** — every rule in the spec has a "When to deviate" escape hatch, because a rigid system is one people route around.

## Safety

- Never overwrite existing `DESIGN_SYSTEM.md`, `tokens.ts`, or primitives without explicit confirmation
- Don't edit CSS theme files — those are content; this skill only writes the utility bridge
- If the project uses a non-shadcn framework (Chakra, MUI), abort and tell the user — this skill's opinions don't transplant
- The skill writes files and commits nothing. Chain with `/ro:commit` for the "just scaffolded" commit

## See also

- `/ro:design-system-audit` — run after scaffolding to find callers that still violate the rules
- `/ro:frontend-design` — broader UI review skill; this one is narrower and more actionable
- `/ro:coding-principles` — simplicity principles that informed the "rules not laws" choice
