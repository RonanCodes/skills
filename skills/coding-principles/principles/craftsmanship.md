# Craftsmanship

## Boy Scout Rule

Leave code better than you found it. Small improvements while you're there.

Do: rename a confusing variable, add a missing type, extract a helper, remove dead code.
Don't: rewrite entire modules while fixing a typo. Big improvements are separate tasks.

```typescript
// Before — fixing a bug, notice confusing name
function calc(d: number[]) {
  return d.reduce((a, b) => a + b, 0) / d.length;
}

// After — bug fixed AND code improved
function calculateAverage(numbers: number[]): number {
  return numbers.reduce((sum, n) => sum + n, 0) / numbers.length;
}
```

## Principle of Least Surprise

Code should behave the way the name suggests. No hidden side effects.

```typescript
// Surprising — "get" shouldn't modify state
function getUser(id: string): User {
  this.lastAccessedUser = id; // hidden side effect
  return this.users.get(id);
}

// Not surprising
function getUser(id: string): User {
  return this.users.get(id);
}
```

Red flags: a `save()` that also sends an email, a constructor that makes network requests, a getter that throws.

## Composition over Inheritance

Prefer combining objects over class hierarchies. Inheritance creates rigid, fragile trees. Composition is flexible and testable.

```typescript
// Inheritance — Penguin extends Bird but can't fly. Awkward.
class Bird extends Animal { fly() { ... } }
class Penguin extends Bird {
  fly() { throw new Error("Can't fly!"); }
}

// Composition — capabilities are assembled
interface Movable { move(): void; }
interface Swimmable { swim(): void; }

class Penguin implements Movable, Swimmable {
  constructor(private mover: Movable, private swimmer: Swimmable) {}
  move() { this.mover.move(); }
  swim() { this.swimmer.swim(); }
}
```

When inheritance IS appropriate: true "is-a" relationships (rare), and when you need both polymorphism and shared implementation.
