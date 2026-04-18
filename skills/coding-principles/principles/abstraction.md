# Abstraction

## Rule of Three

- First time: just write the code
- Second time: note the duplication, resist abstracting
- Third time: now you have enough examples to abstract correctly

Wrong abstractions are worse than duplication. Duplicated code is easy to change; wrong abstractions are not.

```typescript
// First two times — just duplicate
function validateEmail(email: string) { ... }
function validateUsername(username: string) { ... }

// Third time — now you see the pattern
function validateField(value: string, rules: ValidationRule[]): ValidationResult { ... }
```

## DRY

DRY is about knowledge, not code. Two identical-looking functions can represent different knowledge.

```typescript
// Looks like duplication but different knowledge — this is fine
function calculateShippingTax(amount: number) {
  return amount * 0.08; // Shipping tax rate
}
function calculateProductTax(amount: number) {
  return amount * 0.08; // Product tax rate (same now, different rules)
}

// Actual DRY violation — same knowledge in 5 places
// Fix: single source of truth
const TAX_RATE = 0.08;
function calculateTax(amount: number) {
  return amount * TAX_RATE;
}
```

## Single Source of Truth

Each piece of data or logic has one authoritative source. All other usages reference it.

```typescript
// Violation — type defined in two places, will drift
// api/types.ts
type Status = 'pending' | 'active' | 'closed';
// frontend/types.ts
type Status = 'pending' | 'active' | 'closed';

// Single source
// shared/constants.ts
export const STATUSES = ['pending', 'active', 'closed'] as const;
export type Status = typeof STATUSES[number];
```
