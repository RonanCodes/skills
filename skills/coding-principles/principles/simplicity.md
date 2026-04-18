# Simplicity

## KISS

Red flags you're violating it:
- "This is clever" (clever = hard to maintain)
- Adding abstractions "just in case"
- Solution requires extensive docs to understand

```typescript
// Over-engineered
class StringFormatterFactory {
  createFormatter(type: FormatterType): IStringFormatter { ... }
}

// KISS
function formatName(first: string, last: string): string {
  return `${first} ${last}`;
}
```

## YAGNI

The cost of violations: code to write and test that may never be used, complexity that slows real work, abstractions that won't fit when the real requirement arrives.

```typescript
// YAGNI violation
interface UserService {
  getUser(id: string, options?: {
    includeDeleted?: boolean;
    cacheStrategy?: CacheStrategy;
    transformers?: UserTransformer[];
  }): Promise<User>;
}

// Build what you need now
interface UserService {
  getUser(id: string): Promise<User>;
}
```

## No Premature Optimization

Optimize only when:
- You have profiling data showing a bottleneck
- It's in a hot path (called frequently)
- The gain is measurable and significant

```typescript
// Premature — sacrificing readability
const users = data.reduce((acc, d) => (d.type === 'user' && (acc[d.id] = d), acc), {});

// Clear first, optimize if needed
const users = data
  .filter(d => d.type === 'user')
  .reduce((acc, user) => ({ ...acc, [user.id]: user }), {});
```
