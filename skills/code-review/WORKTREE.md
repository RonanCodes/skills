# Code Review — Worktree mode

How to review PRs side-by-side with `main` using a reusable git worktree, so you can run both apps simultaneously and visually compare.

The worktree is generic (`<repo>-code-review`), not per-PR. You set it up once per repo, then switch the same worktree between PRs as you review them. This avoids paying the `pnpm install` cost every time.

## Quick start

```bash
# One-time per repo: create the code-review worktree, install deps, apply migrations
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh 171

# Switch to a different PR (reuse the worktree, no fresh install)
~/Dev/ronan-skills/skills/code-review/scripts/setup-pr-worktree.sh --switch 195

# Start dev on alternate port
cd ../<repo>-code-review
pnpm dev -- --port 3001

# Compare:
open http://localhost:3000   # main
open http://localhost:3001   # PR
```

Both servers can run at the same time. Their local D1 / KV / R2 state is automatically isolated because Wrangler's `.wrangler/state/` lives per-cwd.

## What the script does

1. **Detects the repo.** Uses `git rev-parse --show-toplevel`, or `--repo <path>`.
2. **Detects the package manager.** pnpm > yarn > bun > npm based on lockfile.
3. **Detects the D1 binding.** Reads `wrangler.jsonc` / `wrangler.toml` for `database_name`.
4. **Creates the worktree** at `../<repo>-code-review` on the PR's head branch.
5. **Copies `.dev.vars`** (and `.env.local` if present) from the main checkout.
6. **Installs dependencies** (pnpm/npm/yarn/bun install) in the worktree.
7. **Applies D1 migrations** to the worktree's local SQLite (isolated from main).
8. **Prints next steps** with the dev-server command and Clerk redirect-URL reminder.

`--switch <PR>` reuses the existing worktree, fetches the new branch, hard-resets to it, and reruns migrations. Skips the `pnpm install` step.

## Side-by-side dev — the full table

| Concern | Default | What to do |
|---------|---------|------------|
| **Port** | Most TanStack Start / Vite repos hardcode `--port 3000` in the `dev` script | Override: `pnpm dev -- --port 3001`. The `--` forwards the flag through pnpm to vite. |
| **Local D1** | `.wrangler/state/v3/d1/<id>.sqlite` lives per cwd | Automatically isolated. Each worktree has its own SQLite. Migrations run once per worktree. |
| **Local KV / R2** | Same as D1 — `.wrangler/state/` per cwd | Automatically isolated. |
| **`.dev.vars`** | Gitignored, doesn't follow the worktree | Script copies from main. Edit if any value is port-specific. |
| **Clerk callbacks** | Dev keys whitelist exact redirect URIs | Add `http://localhost:3001` (or whichever alt port) to Clerk dashboard → Paths or Allowed origins. One-time setup; both ports work after. |
| **OAuth providers** (Google, Shopify) | Same as Clerk — exact redirect URI match | Add the alt-port callback URL to each provider's app config once. |
| **External webhooks** (Stripe, Resend, Nango) | Tunnels resolve to one URL | Only one worktree can claim the public webhook URL at a time. Stop the tunnel on main when you want the PR worktree to receive webhooks. Not a blocker for visual review. |
| **Third-party API in mutate mode** | Shared upstream | Read-only flows are fine on both. Writing from both into the same Shopify dev store / Nango sandbox can race. Pick one worktree for write flows. |
| **Browser cookies** | One origin = one cookie jar | Use a separate Chrome profile or incognito window for the alt-port app if the auth cookies collide. |
| **Service worker** | Registered per origin (`localhost:3000` vs `localhost:3001` are different origins) | Naturally isolated. No collision. |

## Recipe — running both at once

```bash
# Terminal 1 — main
cd ~/Dev/projects/<repo>
pnpm dev                            # listens on :3000

# Terminal 2 — PR
cd ~/Dev/projects/<repo>-code-review
pnpm dev -- --port 3001             # listens on :3001
```

The first time you open `http://localhost:3001` and try to sign in with Clerk, you may get a redirect-URI mismatch. Add `http://localhost:3001` (and the post-sign-in path, e.g. `http://localhost:3001/dashboard`) to your Clerk dashboard's allowed origins / redirect URLs. After that, both ports work forever.

## When NOT to use the worktree

- The PR is trivial (one-file fix) — `gh pr checkout` in place is faster than spinning up the worktree.
- The PR has no UI changes — there's nothing to visually compare; just read the diff.
- You're on a small disk and a full `node_modules` copy would matter — though pnpm's content-addressable store usually means the worktree's `node_modules` is mostly symlinks, so the on-disk cost is small.

## Troubleshooting

**`pnpm dev -- --port 3001` ignores the port.**
Some `dev` scripts call `vite dev --port 3000` directly, in which case the trailing `--port 3001` is appended but vite uses the last value. If override isn't working, run `npx vite dev --port 3001` directly, bypassing the package script.

**Clerk "redirect URI mismatch" on the alt port.**
Add `http://localhost:3001` and `http://localhost:3001/*` to the allowed origins in the Clerk dashboard. Same for Google Cloud Console (OAuth client → Authorized redirect URIs) if you're hitting Google APIs.

**Cookies / auth collide between the two ports.**
Open the PR app in an incognito window or a separate Chrome profile. Cookies are scoped to `(domain, port)` for `Set-Cookie` purposes but browsers will sometimes show stale state; incognito is the simplest reset.

**D1 schema differs between PRs and you forgot to re-migrate.**
The `--switch` flag reruns `wrangler d1 migrations apply <db> --local` for you. If you switched manually with `git checkout`, run that command in the worktree before starting dev.

**`pnpm install` is slow every time.**
You shouldn't need to re-run it — pnpm picks up the new branch's `pnpm-lock.yaml` and only installs the diff. If it's slow, check `~/Library/pnpm/store` isn't being garbage-collected.

**Worktree gets stuck on a branch you've already merged.**
`git worktree remove ../<repo>-code-review --force` then re-run the setup script. Worktrees are cheap to recreate.
