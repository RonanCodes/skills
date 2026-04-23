---
name: design-system-audit
description: Scan a repo for violations of its DESIGN_SYSTEM.md — hand-rolled buttons, hex colours, radius that changes across states, scale-based active states, missing hover/focus/disabled treatment. Prints a prioritised punch list. Use before shipping a UI polish or when a design system was recently introduced and callers haven't migrated yet.
category: frontend
argument-hint: [--path=src/] [--fix-obvious] [--skip history]
---

# Design System — Audit

Finds the places where the UI drifts from the spec. Outputs a grouped, priorities punch list — not a silent rewrite. Pairs with `/ro:design-system-create`; either skill works standalone but this one reads `DESIGN_SYSTEM.md` to calibrate strictness.

## Usage

```
/ro:design-system-audit                       # scan src/ with repo's DESIGN_SYSTEM.md
/ro:design-system-audit --path=src/components # narrow scope
/ro:design-system-audit --fix-obvious         # apply safe autofixes (hex → token, add Button import)
/ro:design-system-audit --severity=warn       # include style nits, not just violations
```

## What gets checked

| Check | Severity | Signal |
|---|---|---|
| Hand-rolled `<button className="...">` with bg/hover utilities | 🔴 Critical | Not using Button primitive |
| Radius differs across states on the same element (`rounded-md ... active:rounded-lg`) | 🔴 Critical | Violates rule #1 |
| `scale-1[01]0` or `scale-105` on active/hover | 🔴 Critical | Violates rule #2 (active = pressed, not emphasised) |
| Hex colour in component source (`#[0-9a-f]{3,8}`) | 🟡 Warning | Should come from token |
| `rounded-\[\d+px\]` one-off | 🟡 Warning | Violates rule #6 (single scale) |
| Hover with no active/focus/disabled counterpart | 🟡 Warning | Violates rule #3 (all states) |
| Custom focus ring (`focus:ring-\[...` that isn't the canonical 3px ring-ring/50) | 🟡 Warning | Violates rule #4 |
| Raw `<input>` with className (not `<Input>`) | 🟡 Warning | Not using Input primitive |
| Text size bracket (`text-\[1[0-9]px\]`) | 🔵 Info | Should use TYPOGRAPHY token |
| Padding bracket (`p[xy]?-\[\d+px\]`) | 🔵 Info | Should use SPACING scale |
| Z-index literal in style prop | 🔵 Info | Should use Z token |

Severity is calibrated by `DESIGN_SYSTEM.md` — if the spec says "no hex", hex is 🔴; if the spec is silent, it's 🟡.

## Process

### 1. Locate the spec

```bash
test -f DESIGN_SYSTEM.md || { echo "No DESIGN_SYSTEM.md — run /ro:design-system-create first"; exit 1; }
```

Parse the six core rules out of the spec (look for the `## Core rules` section). If rules 1–6 don't match the canonical set, honour whatever's actually there — the spec is source of truth, not this skill.

### 2. Locate the primitives

```bash
ls src/components/ui/{button,input,card}.tsx 2>/dev/null
grep -rn 'export.*Button\b' src/components/ | head
```

Capture the import path(s) so the report can recommend `import { Button } from '<path>'` correctly.

### 3. Run the scans

All scans are `rg` patterns against files in `--path` (default `src/`), excluding `src/components/ui/`, `node_modules`, and generated code. Each violation records: file, line, matched text, rule number, suggested fix.

**Hand-rolled buttons:**

```bash
rg -n --type tsx --type ts \
  '<button\b[^>]*className=' \
  src/ --glob '!src/components/ui/**'
```

For each hit, show the line, the classes used, and propose the nearest matching `<Button variant="...">`:
- bg-primary → `variant="default"`
- border + bg-background → `variant="outline"`
- text-primary + underline-offset → `variant="link"`
- no bg, only hover:bg-accent → `variant="ghost"`
- bg-destructive → `variant="destructive"`

**Scale-on-state violations (rule #2):**

```bash
rg -n --type tsx --type ts \
  '(hover|active|focus|data-\[state=\w+\]):scale-' \
  src/ --glob '!src/components/ui/**'
```

Each match = a toggle/button using "emphasis" for what should be "pressed" or vice versa. Proposed fix: replace scale with `active:translate-y-px` for pressed, filled-and-bordered toggle pattern for on/off.

**Radius drift (rule #1):**

Multi-line regex — looks for `rounded-*` appearing in a state variant (hover:, active:, data-[state=open]:) that doesn't match the base:

```bash
rg -nU --type tsx --type ts \
  'className=\{[^}]*rounded-\w+[^}]*(hover|active|data-\[state=\w+\]):rounded-\w+' \
  src/ --glob '!src/components/ui/**'
```

Manual verification needed — `rg` is permissive here. Flag as "review" not "fix" unless clearly a drift.

**Hex colours in components (rule #5):**

```bash
rg -n --type tsx --type ts \
  '#[0-9a-fA-F]{3,8}\b' \
  src/components/ --glob '!src/components/ui/**' \
  --glob '!src/lib/themes/**' \
  | grep -vE '(gitleaks:allow|eslint-disable)'
```

Map common hexes to tokens the repo has: `#ffffff` → `bg-background`, `#000000` → `text-foreground`, project-specific brand colours need human judgement.

**Missing hover/focus/disabled on interactive elements:**

Heuristic: any element with an onClick that isn't a `<Button>` or `<Link>` should have all four states. Scan for onClick handlers + className, then check the className string contains `hover:`, `focus-visible:` or `focus:`, `disabled:`. Report missing.

**Radius one-offs (rule #6):**

```bash
rg -n 'rounded-\[[\d.]+(px|rem)\]' src/ --glob '!src/components/ui/**'
```

**Bracket sizes / paddings:**

```bash
rg -n 'text-\[[\d.]+px\]|p[xyltrb]?-\[[\d.]+px\]' src/ --glob '!src/components/ui/**'
```

### 4. Report

Grouped by severity, not by file. Under each item: the file:line, the offending snippet, the rule it breaks, and the concrete fix.

```
🎨 Design System Audit — <project>
   Spec: DESIGN_SYSTEM.md (6 rules) | Scope: src/ | 34 files scanned

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL — fix before shipping
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1] Hand-rolled button (not <Button>)
    src/App.tsx:798
    <button onClick={() => setExpanded(!expanded)} className="w-full text-xs px-3 py-2.5 rounded-lg ...">
    Rule: primitives enforce the state table; raw <button> bypasses it.
    Fix:
      <Button variant="ghost" size="sm" onClick={...}>
        {expanded ? 'Less' : `${n} more definitions`}
      </Button>

[2] Scale on toggle state (rule #2 — active ≠ emphasised)
    src/components/Toolbar.tsx:44
    showColor ? 'scale-110 bg-black/10' : 'hover:scale-105 ...'
    Fix: replace with filled-and-bordered on state, translate-y-px for pressed.
    See DESIGN_SYSTEM.md > Toggle vs Active.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟡 WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[3] Hex colour in component (3 occurrences)
    src/components/Banner.tsx:12    background: '#efefe6'
    src/components/Banner.tsx:13    color: '#121212'
    Fix: use var(--card) / var(--foreground) or bg-card / text-foreground.

[4] Radius one-off
    src/components/Chip.tsx:8    className="... rounded-[7px] ..."
    Fix: use rounded-md (6px) or rounded-lg (8px).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔵 INFO — nice to clean up
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[5] Text size bracket
    src/App.tsx:1003    'text-[10px]'
    Fix: text-xs (12px) is the smallest on the scale; if 10px is intentional,
         add `tiny` to TYPOGRAPHY and use TYPOGRAPHY.tiny.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 2 critical · 2 warning · 1 info
Verdict: 🚫 Migrate critical items, then re-audit.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If zero critical:
```
Verdict: ✅ On-spec. Warnings optional, info is polish.
```

### 5. After the report

Via `AskUserQuestion`:

1. **Walk me through fixes** — go critical → warning, one call site at a time, edit in place
2. **Just the one-shot autofix** — apply `--fix-obvious` (hex → token, add Button import, remove scale classes) and commit
3. **I'll handle it** — exit, leave the punch list

### 6. Autofix (opt-in)

Under `--fix-obvious`, the skill will:

- Replace `scale-110`/`scale-105` in state modifiers with `translate-y-px` on active, remove on hover
- Swap clear hex → token mappings (background/foreground/border) where confidence is high
- Add `<Button>` imports and convert buttons whose className pattern unambiguously maps to a variant

It will NOT:

- Delete or rewrite component logic
- Touch anything outside `--path`
- Edit CSS theme files (those are content, not drift)
- Make the change + commit silently — always prints a diff first

## Design decisions this skill bakes in

- **Spec as authority, skill as lens** — the skill reads rules out of `DESIGN_SYSTEM.md`; it never imposes rules the spec doesn't have.
- **Grouped by severity, not by file** — you fix all the "scale on active" instances together because they're one mental switch. File-grouped output makes that harder.
- **Punch list, not silent rewrite** — design drift is often intentional (deviation). Humans decide; the skill proposes.
- **Ignore the primitive files themselves** (`src/components/ui/**`) — they're where the rules live, so matches there are almost always legitimate internal state plumbing.

## Safety

- Never autofix without a dry-run diff shown first
- Respect `// design-system:allow` inline comments — treat as explicit deviation
- If `DESIGN_SYSTEM.md` is stale or the project has diverged intentionally, surface it: "Your spec says X but Y% of call sites use Z; consider updating the spec."
- Don't run against generated code (`dist/`, `.next/`, `build/`, `drizzle/`)

## See also

- `/ro:design-system-create` — scaffold the spec + primitives before auditing
- `/ro:close-the-loop` — visual regression complement; catches drift the linter can't see
- `/ro:coding-principles` — the Boy Scout Rule applied to UI
