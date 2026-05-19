# Canon: D1 migrations

The rule for any Cloudflare D1 + Drizzle app on the stack: **schema migrations go through `wrangler d1 migrations apply`. Raw `wrangler d1 execute --file=<f>` is only for seed data.**

## The rule

| Use case | Command | Why |
|---|---|---|
| Apply schema migration to remote D1 | `wrangler d1 migrations apply <db> --remote` | Reads the local migrations dir + the remote `d1_migrations` tracking table; applies only NEW migrations. Idempotent and stateful. |
| Apply schema migration to local D1 | `wrangler d1 migrations apply <db> --local` | Same idea, against the local SQLite under `.wrangler/`. |
| Re-load seed data | `wrangler d1 execute <db> --remote --file=<seed.sql>` | INSERT-OR-IGNORE seed rows are safe to re-run. State is in the rows themselves. |
| One-time setup, ad hoc query | `wrangler d1 execute <db> --remote --command="<SQL>"` | Doesn't fit either pattern. |

## What NOT to do

A `for f in migrations/*.sql; do wrangler d1 execute --file=$f; done` loop in the deploy workflow. Reasons:

1. **Fires N API calls per deploy** where N is the migration count. After ~50 deploys with 10+ migrations, you trip CF Workers API rate-limit 10429 and get throttled for hours.
2. **Hides failures behind `|| true`.** `CREATE TABLE` on an already-existing table errors; the `|| true` suffix swallows it. Looks like everything works; on a fresh DB a real schema bug would also be swallowed.
3. **No state tracking.** You can't tell what's been applied without `psql`-equivalent introspection.

## How `wrangler d1 migrations apply` tracks state

On first run, wrangler creates a `d1_migrations` table on the database:

```sql
CREATE TABLE d1_migrations (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Each subsequent call reads `d1_migrations.name`, compares against filenames in the configured `migrations_dir` (set via `wrangler.jsonc`'s `d1_databases[].migrations_dir`, defaults to `./migrations`), and only applies files whose name isn't already in the table. Applied migrations get a new row.

Drizzle's `drizzle-kit generate` emits files at `drizzle/NNNN_<tag>.sql` with `drizzle/meta/_journal.json` listing them in order. Set `migrations_dir: "drizzle"` in `wrangler.jsonc` and `wrangler d1 migrations apply` reads them directly.

`d1_migrations` is NOT the same as Drizzle ORM's `__drizzle_migrations` table. The latter is only used if you call Drizzle's `migrate()` from app code (which isn't the stack pattern on D1 — wrangler is the migration runner). Don't mix them.

## Switching an existing app from the brute-force loop

If an app was set up with the wrong pattern (loop + raw execute), the prod D1 has every migration applied but the `d1_migrations` table doesn't exist. Switching to `migrations apply` cold would re-run 0000 and fail on the first `CREATE TABLE`.

Sync script (run ONCE manually before merging the workflow switch):

```sql
CREATE TABLE IF NOT EXISTS d1_migrations (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS d1_migrations_name_unique ON d1_migrations(name);

INSERT OR IGNORE INTO d1_migrations (name) VALUES ('0000_<tag>.sql');
INSERT OR IGNORE INTO d1_migrations (name) VALUES ('0001_<tag>.sql');
-- ...up to the last migration that's already applied on prod.
```

Generate the names by `ls drizzle/*.sql`. Skip any migration that has NOT yet successfully run on prod — let `migrations apply` apply those for real on the next deploy.

Real incident: lekkertaal 2026-05-19. The 12-migration backlog × ~20 deploys/day tripped rate-limit 10429 hard enough that the cooldown outlasted six 5-minute retries. Cleanup PR: `RonanCodes/lekkertaal#169` (workflow swap + sync script + path-filter).

## Required workflow shape

The new-tanstack-app scaffolder emits the right shape. If you're hand-rolling a workflow or auditing an existing one, the deploy job must:

1. Use `cloudflare/wrangler-action@v3` (not raw `pnpm wrangler`)
2. Migration step uses `command: d1 migrations apply <db> --remote`
3. The `push` trigger has `paths-ignore` to skip docs / retro / chore-artefact pushes

The full template lives in [[skill:new-tanstack-app]] § "13. GitHub CI + auto-deploy".

## See also

- [[skill:new-tanstack-app]] — the scaffolder that emits a correct workflow
- [[skill:cf-ship]] — the local pre-flight + deploy command (uses the same migration runner)
- [[canon:labels]] — sibling canon for the GH label system
- `cloudflare/wrangler-action@v3` — the canonical Action: https://github.com/cloudflare/wrangler-action
- `wrangler d1 migrations` docs — https://developers.cloudflare.com/workers/wrangler/commands/#d1-migrations-apply

## Provenance

- **2026-05-19** — written after the lekkertaal incident. Lekkertaal had been deploying with a brute-force `for f in drizzle/*.sql; do wrangler d1 execute --file=$f` loop; 20 deploys × 13 migration files × 1 API call each tripped CF Workers rate-limit 10429 with a cooldown that outlasted multiple retry windows. Dataforce was already on the correct pattern. The canonical fix is in PR `RonanCodes/lekkertaal#169`; this doc names the rule so it doesn't recur.
