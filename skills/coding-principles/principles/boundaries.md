# Boundaries

## Separation of Concerns

Divide into distinct sections, each addressing a separate concern.

```typescript
// Mixed — validation, business logic, data access, and UI in one function
async function handleFormSubmit(formData: FormData) {
  if (!formData.email.includes('@')) {
    document.getElementById('error').textContent = 'Invalid email';
    return;
  }
  const user = { ...formData, createdAt: new Date() };
  await fetch('/api/users', { method: 'POST', body: JSON.stringify(user) });
  document.getElementById('success').style.display = 'block';
}

// Separated
const validateUser = (data: FormData): ValidationResult => { ... };
const createUser = (data: FormData): User => { ... };
const saveUser = async (user: User): Promise<void> => { ... };
const showSuccess = (): void => { ... };
```

## Law of Demeter

Only talk to immediate friends. Chains like `a.getB().getC().doSomething()` mean you're reaching through objects.

```typescript
// Reaching through — fragile, coupled to internal structure
function getCustomerCity(order: Order): string {
  return order.getCustomer().getAddress().getCity();
}

// Ask the object directly
function getCustomerCity(order: Order): string {
  return order.getShippingCity();
}
```

## Principle of Least Privilege

Functions receive only the data they need. Private by default.

```typescript
// Receives entire User but only needs email and name
function sendWelcomeEmail(user: User) {
  mailer.send(user.email, `Welcome ${user.name}!`);
}

// Least privilege
function sendWelcomeEmail(email: string, name: string) {
  mailer.send(email, `Welcome ${name}!`);
}
```
