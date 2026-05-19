// Neon (Postgres) client factory.
//
// Uses the `@neondatabase/serverless` HTTP driver so it works inside
// Cloudflare Workers (no TCP sockets required). Wraps with drizzle's
// `neon-http` adapter for type-safe queries via the schema in
// drizzle/neon/schema.ts.
//
// Usage from a route or server function:
//   import { env } from 'cloudflare:workers'
//   import { getNeonClient } from '~/db/neon'
//   const db = getNeonClient(env)
//   const user = await db.select().from(users).where(eq(users.email, 'me@example.com'))
//
// The NEON_DATABASE_URL binding is a wrangler secret (not a var) so it does
// not appear in wrangler.toml vars. Set it via:
//   wrangler secret put NEON_DATABASE_URL --env production
// For local dev, add NEON_DATABASE_URL to .dev.vars.

import { neon } from '@neondatabase/serverless'
import { drizzle } from 'drizzle-orm/neon-http'
import * as schema from '../../drizzle/neon/schema'

export interface NeonEnv {
  NEON_DATABASE_URL: string
}

export function getNeonClient(env: NeonEnv) {
  if (!env.NEON_DATABASE_URL) {
    throw new Error(
      'NEON_DATABASE_URL is not set. Add it to .dev.vars for local dev, ' +
        'or run: wrangler secret put NEON_DATABASE_URL --env production',
    )
  }
  const sql = neon(env.NEON_DATABASE_URL)
  return drizzle(sql, { schema })
}

export type NeonDb = ReturnType<typeof getNeonClient>

export { schema }
