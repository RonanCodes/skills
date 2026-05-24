---
name: ship
description: Ship a feature branch the local-CI-first way — run the full local gate, push, open a PR, squash-merge, then deploy, without waiting on GitHub Actions. Use when a branch is ready for main and you want it merged and deployed now. Reads CI policy from `ro ci` (default skips remote CI because GitHub Actions billing keeps hitting limits). Sibling to /ro:gh-ship (waits on GitHub checks) and /ro:cf-ship (the deploy half). Triggers on "ship it", "ship this", "merge and deploy", "land this PR", "skip CI and merge".
category: development
argument-hint: [--no-deploy] [--require-remote-ci] [--title "<title>"]
allowed-tools: Bash(git *) Bash(gh *) Bash(ro *) Bash(jq *) Bash(pnpm *) Bash(npx *) Read AskUserQuestion
---

# ship — local CI is the gate, GitHub is just the record

The premise: GitHub Actions billing keeps hitting spending limits, so waiting on
remote CI stalls every merge. We don't want to wait on it. Instead the **local
git hooks are the real gate** (pre-commit formats, pre-push runs the full local
CI), and once the local gate is green we open the PR and squash-merge straight
away, then deploy. GitHub still records the PR; it just isn't the gate.

This is the default. A project can opt back into waiting on remote CI by setting
`remoteCI: "require"` (see **Policy** below), in which case this skill behaves
like `/ro:gh-ship`.

## Non-negotiables (the canon)

1. **Never push to `main`.** Always a feature branch → PR → **squash-merge**.
2. **Local CI is the gate.** The pre-push hook runs build + lint + format-check +
   typecheck + test (+ e2e where it's fast). If that's green, the code is good.
3. **Squash-merge only.** One commit per PR on `main`.
4. **Deploy right after merge** (unless `autoDeploy: false` or `--no-deploy`).

## Policy resolution

Read it, don't hardcode it:

```bash
ro ci show                 # full resolved policy
ro ci get remoteCI         # "skip" | "require"
ro ci get mergeOnLocalPass # bool
ro ci get autoDeploy       # bool
```

Resolution order (later wins): built-in default → `~/.claude/ci-policy.json`
(global) → `.ro-ci.json` (committed, repo-declared) → `.ro-ci.local.json`
(gitignored, personal override). Set the global once with `ro ci init` then edit.

`--require-remote-ci` forces `remoteCI=require` for this run; `--no-deploy`
forces `autoDeploy=false`.

## Flow

```
1. Guard: refuse if on main/master. If on main, stop and tell the user to branch.
2. Ensure work is committed (defer to /ro:commit for message + timestamp rules).
3. Run the local gate explicitly so failures surface here, not just in the hook:
     pnpm quality-checks   (or the repo's equivalent; see "Local gate" below)
   If it fails, stop. Do not push.
4. Push the branch (the pre-push hook re-runs the gate — that's fine, it's fast).
5. Open the PR:  gh pr create --base main --fill   (or --title from arg)
6. Merge, per policy:
     remoteCI == "skip"  and mergeOnLocalPass:
         gh pr merge --squash --admin --delete-branch
         (--admin bypasses the billing-blocked / unstarted remote checks)
     remoteCI == "require":
         watch checks, merge on green — hand off to /ro:gh-ship behaviour.
7. Deploy, if autoDeploy and not --no-deploy:
     defer to the repo's deploy path — /ro:cf-ship (Cloudflare),
     /ro:fly-deploy (Fly), or `pnpm deploy`. Skip for non-deployable repos
     (skills, wiki) — those have no deploy step.
8. Sync local main:  git checkout main && git pull --ff-only
```

If `--admin` is refused (not an admin on the repo), fall back to: report that the
merge needs either admin rights or remote CI, and ask the user how to proceed.

## Local gate

The gate is whatever the repo's pre-push hook runs. For the standard pnpm repo
that's the `quality-checks` script:

```
prettier --check . && eslint && astro check && astro build && vitest run
```

Plus Playwright e2e where it stays fast. **Perf budget:** the whole gate should
finish in a couple of minutes. If it creeps past ~3–4 min, investigate and trim
(Docker-in-the-loop and slow full-browser matrices are the usual culprits) rather
than living with a gate nobody waits for. A gate that's too slow gets skipped,
which defeats the point.

## The standard hook set (every repo)

Apply this set to any repo following the policy (see /ro:git-guardrails for the
guard details):

| Hook | Runs | Why |
|---|---|---|
| `pre-commit` | `lint-staged` (prettier --write on staged) | never commit unformatted code |
| `commit-msg` | `commitlint --edit "$1"` | enforce emoji-conventional commits |
| `pre-push` | full local CI **+ refuse pushes to main** | the real gate; protect main |

The pre-push main-guard:

```sh
while read -r _ _ remote_ref _; do
  case "$remote_ref" in refs/heads/main|refs/heads/master)
    echo "✋ Direct push to main is not allowed. Open a PR and squash-merge." >&2
    exit 1 ;;
  esac
done
```

Belt-and-braces: also set GitHub branch protection requiring a PR
(`gh api -X PUT repos/{owner}/{repo}/branches/main/protection ...`) so main is
protected even when hooks aren't installed. **Caveat:** branch protection needs
GitHub Pro for *private* repos (free returns "Upgrade to GitHub Pro or make this
repository public"). For private repos on the free plan, the pre-push main-guard
is the only enforcement — make sure the hook is installed.

## Notes

- This skill assumes commits already exist or are trivially made; it is not a
  commit tool. Use /ro:commit for staging + message + weekday-timestamp rules.
- For the GitHub-checks-as-gate flow (open-source repos, shared CI you trust),
  use /ro:gh-ship instead — same shape, but it waits on the checks.
