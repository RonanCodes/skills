---
name: harden-npm
description: Apply npm/pnpm/bun supply-chain hardening to a repo. Pins packageManager, writes per-repo .npmrc with minimum-release-age + ignore-scripts, audits GitHub Actions for pull_request_target, installs husky pre-push hook if missing, optionally runs pnpm approve-builds. Idempotent and safe to re-run. Auto-invoked by /ro:new-tanstack-app and /ro:new-app. Use after any /ro:migrate-* or whenever a repo needs supply-chain controls brought up to canon.
category: quality
argument-hint: [path] [--check] [--no-husky] [--no-approve-builds]
allowed-tools: Bash Read Write Edit Glob Grep AskUserQuestion
---

# Harden npm/pnpm/bun

Apply supply-chain hardening defaults to a JS/TS repo. The defensive set codified after the Mini Shai-Hulud v2 (TanStack) attack, CVE-2026-45321.

## When to use

- Before merging any new repo into the canonical-stack set
- After `/ro:new-tanstack-app` or `/ro:new-app` (auto-invoked)
- After `/ro:migrate-to-tanstack` or `/ro:migrate-to-astro` (any framework migration)
- On any existing repo that is older than 2026-05-18 and has not been hardened yet
- As a periodic re-run (idempotent) to pick up new versions of pnpm

## Usage

```
/ro:harden-npm                          # apply to cwd
/ro:harden-npm /path/to/repo            # apply to a specific repo
/ro:harden-npm --check                  # audit only, no writes (report what would change)
/ro:harden-npm --no-husky               # skip husky pre-push step
/ro:harden-npm --no-approve-builds      # skip the interactive pnpm approve-builds walk
```

## What it does

Six concrete changes. All idempotent. All skip-if-already-applied.

| # | Action | Why |
|---|---|---|
| 1 | Upgrade pnpm to v11+ via corepack (global), pin packageManager in package.json | pnpm 11 ships minimumReleaseAge=1440, strictDepBuilds=true, blockExoticSubdeps=true as defaults |
| 2 | Write per-repo `.npmrc` with minimum-release-age, ignore-scripts, save-exact, prefer-frozen-lockfile | Defence in depth: explicit per-repo policy that survives pnpm major-version changes; npm-fallback compatibility |
| 3 | Walk `pnpm approve-builds` to populate `pnpm.onlyBuiltDependencies` allowlist | Block lifecycle scripts by default, whitelist the few that genuinely need a build step (sharp, esbuild, @cloudflare/workerd, sqlite3) |
| 4 | Install + wire husky pre-push hook running typecheck + lint + test | Local CI gate; catches regressions before they leave the machine |
| 5 | Audit `.github/workflows/` for `pull_request_target` triggers | Root-cause vector in the TanStack attack; force a deliberate fence or migration to `pull_request` |
| 6 | Quick worm-payload scan of `node_modules` for known signatures (`bundle.js`, `shai-hulud`, 60s-poller patterns) | Sanity check: confirm nothing infected slipped in pre-hardening |

## Steps

1. **Resolve repo path** from `[path]` arg or cwd. If not a git repo, error out.

2. **Detect package manager:**
   - Has `pnpm-lock.yaml` → pnpm path
   - Has `bun.lockb` or `bun.lock` → bun path (different recipe, see § Bun)
   - Has `package-lock.json` and no others → npm path (degraded recipe)
   - Has `yarn.lock` → ask the user; recommend migrating to pnpm

3. **Check mode:** if `--check`, report the per-step diff and exit 0. Do not write.

4. **Step 1: pnpm version**

   ```bash
   pnpm -v
   ```

   If < 11: run `corepack prepare pnpm@latest --activate` (global) and verify. Then:

   ```bash
   npm pkg set packageManager="pnpm@$(pnpm -v)"
   ```

   If `packageManager` field already matches `pnpm@11.*`, skip.

5. **Step 2: per-repo `.npmrc`**

   If `.npmrc` does not exist OR does not contain `minimum-release-age=1440`, write or append:

   ```ini
   # Supply-chain hardening — applied by /ro:harden-npm
   # See [security:npm-supply-chain-hardening](obsidian://open?vault=llm-wiki-security&file=wiki%2Fplaybooks%2Fnpm-supply-chain-hardening)
   minimum-release-age=1440
   ignore-scripts=true
   save-exact=true
   prefer-frozen-lockfile=true
   ```

   If `.npmrc` already exists with other settings, preserve them. Insert the new block at the top with a comment marker, only if not already present.

6. **Step 3: approve-builds** (skipped if `--no-approve-builds`)

   Check `package.json` for `pnpm.onlyBuiltDependencies`. If missing:

   - Detect common build-script packages already in dep tree:
     ```bash
     find node_modules -maxdepth 3 -name "package.json" -exec jq -r 'select(.scripts.postinstall or .scripts.preinstall) | .name' {} \; 2>/dev/null | sort -u
     ```
   - Auto-approve the **safe canonical list** if found: `sharp`, `esbuild`, `@cloudflare/workerd`, `@swc/core`, `better-sqlite3`, `sqlite3`, `puppeteer`, `playwright`, `cypress`, `husky`. These are well-known build-step packages with no history of supply-chain incidents. Write them to `pnpm.onlyBuiltDependencies` array in package.json.
   - For anything else found, use AskUserQuestion to surface each unknown postinstall script for review.

   This step is interactive ONLY if unknowns are found. Otherwise silent.

7. **Step 4: husky pre-push** (skipped if `--no-husky`)

   If `package.json` has `husky` as a dev dep AND `.husky/pre-push` exists: append/verify the local-CI line. If file doesn't exist or husky not installed:

   ```bash
   # Only run pnpm add if husky truly missing
   grep -q '"husky"' package.json || pnpm add -D husky
   mkdir -p .husky
   ```

   Write `.husky/pre-push`:

   ```sh
   #!/usr/bin/env sh
   . "$(dirname -- "$0")/_/husky.sh"

   # Local CI gate — catches regressions before they leave the machine
   # Installed by /ro:harden-npm
   pnpm typecheck
   pnpm lint
   pnpm test --run
   ```

   `chmod +x .husky/pre-push`. Make sure `prepare` script in package.json is `husky` (or `husky install` on older versions).

   Detect package-manager-specific script names: if `typecheck` script is missing in package.json, try `tsc --noEmit` directly. Document any substitutions in a comment at the top of the hook.

8. **Step 5: GH Actions audit**

   ```bash
   rg -n "pull_request_target" .github/workflows/ 2>/dev/null
   ```

   If matches found, REPORT them (don't auto-fix). Output the file + line + surrounding context. Surface the [security:github-actions-fork-pr-safety](obsidian://open?vault=llm-wiki-security&file=wiki%2Fplaybooks%2Fgithub-actions-fork-pr-safety) playbook link. Use AskUserQuestion with three options: keep, fence with fork-check, or migrate to `pull_request`.

   This is the only step that can require human judgement — the right fix depends on what the workflow does.

9. **Step 6: worm-payload scan**

   ```bash
   find node_modules -path "*/@tanstack/*" -name "bundle.js" 2>/dev/null
   find node_modules -iname "*hulud*" 2>/dev/null
   grep -rlE "checkGitHubToken|webhook\.site" node_modules 2>/dev/null | head -5
   ```

   If anything matches, STOP and report. Recommend the user nuke `node_modules`, snapshot the machine, then run `/ro:security-audit` for a deeper scan.

10. **Report:** print a summary of which steps changed something vs were already in place. Suggest next: `git diff` + commit on a branch.

11. **Commit:** offer to commit with conventional message:

    ```
    🔒 security: apply /ro:harden-npm supply-chain controls
    
    - pnpm pinned to 11.x.x via packageManager
    - .npmrc: minimum-release-age, ignore-scripts, save-exact
    - husky pre-push wired with typecheck + lint + test
    - approve-builds whitelist: <list>
    - GH Actions audit: <result>
    ```

    Use AskUserQuestion: commit now, commit on a new branch `security/harden-npm`, or stage only. Default to new branch for shared repos.

## Bun recipe

Bun's defence surface differs. Apply this subset:

| Step | Bun equivalent |
|---|---|
| Pin packageManager | `npm pkg set packageManager="bun@$(bun -v)"` |
| minimum-release-age | **Not supported in bun.** Compensate via Renovate `minimumReleaseAge` rule. |
| ignore-scripts | Default in bun. Populate `trustedDependencies` array in package.json with the same safe canonical list as pnpm's `onlyBuiltDependencies`. |
| blockExoticSubdeps | Not directly supported. Audit lockfile manually for non-registry resolutions. |
| approve-builds | Use `trustedDependencies` array instead. |
| husky pre-push | Same as pnpm path. |
| GH Actions audit | Same as pnpm path. |

## npm recipe

Degraded mode. `minimum-release-age` is not supported. Apply:

- `npm pkg set packageManager="npm@$(npm -v)"`
- `.npmrc` with `ignore-scripts=true`, `save-exact=true`
- `npm audit --audit-level=moderate` in pre-push hook
- GH Actions audit (same)

Strongly suggest migrating to pnpm.

## Verification (post-apply)

```bash
pnpm -v                                          # 11.x
cat package.json | jq '.packageManager'          # "pnpm@11.x.x"
cat .npmrc | grep minimum-release-age            # 1440
cat package.json | jq '.pnpm.onlyBuiltDependencies' # populated array
ls -la .husky/pre-push                           # exists, executable
rg "pull_request_target" .github/workflows/      # empty OR fenced
find node_modules -iname "bundle.js" -path "*@tanstack*"  # empty
```

## When NOT to use

- A repo that publishes a package to npm via Trusted Publishing — separate concerns; this skill hardens the **consumer** posture. Publisher posture needs additional workflow auditing per [security:github-actions-fork-pr-safety](obsidian://open?vault=llm-wiki-security&file=wiki%2Fplaybooks%2Fgithub-actions-fork-pr-safety).
- A repo that intentionally pins to a specific older pnpm for compatibility (rare; flag and ask before overriding).
- A repo using yarn-classic or yarn-berry as a deliberate choice (different skill needed).

## See also

- [security:npm-supply-chain-hardening](obsidian://open?vault=llm-wiki-security&file=wiki%2Fplaybooks%2Fnpm-supply-chain-hardening) — full playbook
- [security:mini-shai-hulud-v2-tanstack](obsidian://open?vault=llm-wiki-security&file=wiki%2Fincidents%2Fmini-shai-hulud-v2-tanstack) — incident that triggered this skill
- [research:ideal-tech-setup](obsidian://open?vault=llm-wiki-research&file=wiki%2Fconcepts%2Fideal-tech-setup) — Golden Stack canon (audit checklist § Supply-chain hardening)
- `/ro:security-audit` — pre-publish secrets/PII scan (orthogonal concern, run both)
