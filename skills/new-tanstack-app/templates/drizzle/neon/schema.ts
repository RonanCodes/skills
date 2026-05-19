// Drizzle schema for the Neon (Postgres) store.
//
// Uses `pgTable` from `drizzle-orm/pg-core`. Replace or extend this example
// table with your domain model. Run `pnpm db:generate` after each schema
// change to produce a new migration file.
//
// Dialect: postgresql (Neon is standard Postgres).

import { sql } from 'drizzle-orm'
import { pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core'

// users: minimal example table. Replace with your domain model.
export const users = pgTable('users', {
  id: uuid('id')
    .primaryKey()
    .default(sql`gen_random_uuid()`),
  email: text('email').notNull().unique(),
  name: text('name'),
  createdAt: timestamp('created_at', { withTimezone: true })
    .notNull()
    .default(sql`now()`),
})

export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
