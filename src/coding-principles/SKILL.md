---
name: coding-principles
description: Software design principles and opinionated stances on clean code. Reference skill — index is always loaded, detail files read on demand. Use when reviewing code, refactoring, or making architecture decisions.
---

# Coding Principles

Quick reference index. Each section links to a detail file with examples — read those when a specific principle is relevant.

## Simplicity

| Principle | Stance |
|-----------|--------|
| **KISS** | The simplest solution that works wins. "Clever" = hard to maintain. |
| **YAGNI** | Don't build for hypothetical futures. Predicted requirements are usually wrong. |
| **No premature optimization** | Make it work, make it right, make it fast — in that order. Profile before optimizing. |

See: [principles/simplicity.md](principles/simplicity.md)

## Abstraction

| Principle | Stance |
|-----------|--------|
| **Rule of Three** | Don't abstract until you've seen the pattern 3 times. Two is coincidence. |
| **DRY** | About knowledge, not code. Two identical functions can represent different knowledge — that's OK. |
| **Single Source of Truth** | One authoritative place for each piece of data. Derive, don't duplicate. |

See: [principles/abstraction.md](principles/abstraction.md)

## SOLID

| Principle | One-liner |
|-----------|-----------|
| **Single Responsibility** | One reason to change |
| **Open/Closed** | Extend by adding code, not modifying existing code |
| **Liskov Substitution** | Subtypes must be drop-in replacements for base types |
| **Interface Segregation** | Many specific interfaces > one fat interface |
| **Dependency Inversion** | Depend on abstractions, not concretions |

See: [principles/solid.md](principles/solid.md)

## Boundaries

| Principle | Stance |
|-----------|--------|
| **Separation of Concerns** | UI, business logic, and data access are separate. Always. |
| **Law of Demeter** | `a.getB().getC().doThing()` is a red flag. Only talk to immediate friends. |
| **Least Privilege** | Functions receive only the data they need. Private by default. |

See: [principles/boundaries.md](principles/boundaries.md)

## Pragmatic Development

| Principle | Stance |
|-----------|--------|
| **Tracer Bullets** | Build a thin end-to-end slice first. Validate architecture before building features. |
| **Don't Outrun Your Headlights** | Small steps with feedback. Feedback rate is your speed limit. |
| **Fail Fast** | Surface errors immediately. Don't hide them, don't continue in a broken state. |

See: [principles/pragmatic.md](principles/pragmatic.md)

## Craftsmanship

| Principle | Stance |
|-----------|--------|
| **Boy Scout Rule** | Leave code better than you found it. Small improvements, not rewrites. |
| **Least Surprise** | If a function name says "get", it shouldn't modify state. No hidden side effects. |
| **Composition over Inheritance** | Prefer combining objects over class hierarchies. Inheritance is rarely the right call. |

See: [principles/craftsmanship.md](principles/craftsmanship.md)

## Testing

| Context | TDD? | Notes |
|---------|------|-------|
| **Backend** | **Mandatory** | Write the test first. Business logic bugs are expensive. |
| **Frontend** | Optional | When it adds value — complex logic, utils, critical paths. |

Backend TDD workflow: failing test → minimum code to pass → refactor → repeat.

## When Principles Conflict

1. **Clarity beats cleverness** — when in doubt, be obvious
2. **Context matters** — a prototype has different needs than production
3. **Principles guide, not govern** — know when to break rules deliberately
4. **Rule of Three before DRY** — duplication is cheaper than the wrong abstraction
