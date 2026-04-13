# Pragmatic Development

## Tracer Bullets

Build a thin, end-to-end slice first to validate architecture. Not a prototype (throwaway) — production code that forms the skeleton.

Building a web app? Tracer bullet = one API endpoint + one DB table + one UI component + one deploy to production. This validates the entire integration before building features.

1. Identify the core path through your system
2. Build a minimal implementation that touches all layers
3. Get it working end-to-end
4. Fill in the details once architecture is validated

## Don't Outrun Your Headlights

Your feedback (tests, types, code review) is your headlights. Don't write more code than you can verify.

```
Write 10 lines → Run tests → Pass? → Commit → Next step
                            Fail? → Fix → Run tests → ...
```

Anti-pattern: write 500 lines → "I'll test it all at the end" → 3 hours debugging.

## Fail Fast

When something goes wrong, fail immediately and visibly. Don't hide errors or continue in a broken state.

```typescript
// Silent failure — hides the real problem
function getUser(id: string): User | null {
  try {
    return database.find(id);
  } catch (e) {
    return null;
  }
}

// Fail fast — errors are visible
function getUser(id: string): User {
  const user = database.find(id);
  if (!user) throw new UserNotFoundError(id);
  return user;
}
```

When NOT to fail fast: user-facing boundaries (friendly errors), systems designed for partial failure, explicit graceful degradation.
