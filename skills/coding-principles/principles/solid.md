# SOLID

## Single Responsibility (SRP)

One class/module, one reason to change.

```typescript
// Violation — three reasons to change
class UserService {
  saveUser(user: User) { ... }        // Database changes
  formatUserEmail(user: User) { ... } // Email format changes
  validateUser(user: User) { ... }    // Validation rule changes
}

// SRP
class UserRepository { saveUser(user: User) { ... } }
class UserEmailFormatter { format(user: User) { ... } }
class UserValidator { validate(user: User) { ... } }
```

## Open/Closed (OCP)

Add new behaviour by adding code, not changing existing code.

```typescript
// Must modify for every new discount type
function calculateDiscount(type: string, amount: number) {
  if (type === 'student') return amount * 0.1;
  if (type === 'senior') return amount * 0.15;
}

// OCP — extend without modifying
interface DiscountStrategy {
  calculate(amount: number): number;
}
class StudentDiscount implements DiscountStrategy {
  calculate(amount: number) { return amount * 0.1; }
}
```

## Liskov Substitution (LSP)

Subtypes must be drop-in replacements. If Square extends Rectangle but breaks `setWidth`/`setHeight` independence, the hierarchy is wrong.

```typescript
// Don't force inheritance where it doesn't fit
interface Shape { getArea(): number; }
class Rectangle implements Shape { ... }
class Square implements Shape { ... }
```

## Interface Segregation (ISP)

Don't force implementations to depend on methods they don't use.

```typescript
// Robot can't eat or sleep — forced to throw
class Robot implements Worker {
  work() { ... }
  eat() { throw new Error('Robots cannot eat'); }
}

// Segregated
interface Workable { work(): void; }
interface Eatable { eat(): void; }
class Robot implements Workable { ... }
```

## Dependency Inversion (DIP)

High-level modules depend on abstractions, not concrete implementations.

```typescript
// Coupled to MySQL
class OrderService {
  private db = new MySQLDatabase();
}

// Inverted — depends on abstraction
class OrderService {
  constructor(private db: Database) {}
}
```
