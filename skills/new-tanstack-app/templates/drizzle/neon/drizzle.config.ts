// Drizzle Kit config for the Neon (Postgres) store.
//
// Generates migrations into ./drizzle/neon/ from drizzle/neon/schema.ts.
// Dialect is `postgresql` because Neon is standard Postgres.
//
// Usage:
//   pnpm db:generate   -> drizzle-kit generate --config drizzle/neon/drizzle.config.ts
//   pnpm db:migrate    -> drizzle-kit migrate  --config drizzle/neon/drizzle.config.ts
//   pnpm db:studio     -> drizzle-kit studio   --config drizzle/neon/drizzle.config.ts
//
// The connection string is read from NEON_DATABASE_URL in the environment.
// Set it in .dev.vars for local dev, or via:
//   wrangler secret put NEON_DATABASE_URL --env production

import { defineConfig } from 'drizzle-kit'

export default defineConfig({
  schema: './drizzle/neon/schema.ts',
  out: './drizzle/neon',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env['NEON_DATABASE_URL'] ?? 'postgres://localhost:5432/myapp',
  },
})
