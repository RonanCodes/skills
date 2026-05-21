---
name: security-audit
description: Pre-publish safety check for a git repo. Scans for secrets/tokens, PII, work identifiers, committed .env files, and risky git history. Use before making a private repo public, before pushing to a new remote, or before sharing a snapshot/zip.
category: quality
argument-hint: [path] [--quick] [--history-only] [--no-personal]
allowed-tools: Bash Read Write Glob Grep
---

# Security Audit

Catches the things you'd be embarrassed (or fired) to ship publicly: API tokens, private keys, customer emails, internal hostnames, your real address in a CONTRIBUTORS file, the `.env` you accidentally committed in 2022 and forgot about.

## Usage

```
/ro:security-audit                    # audit cwd, full scan (working tree + git history)
/ro:security-audit /path/to/repo      # audit a specific repo
/ro:security-audit --quick            # working tree only, skip git history (10× faster)
/ro:security-audit --history-only     # only scan git history (use after fixing working tree)
/ro:security-audit --no-personal      # skip the user's personal-patterns file
```

## What Gets Checked

| Category | Detected by | Severity if found |
|----------|-------------|-------------------|
| **Secrets / API tokens** | gitleaks (100+ token patterns) + custom regex | 🔴 Critical |
| **Private keys** (SSH, PGP, X.509) | gitleaks | 🔴 Critical |
| **Committed `.env` / `.env.*` files** | git ls-files | 🔴 Critical |
| **User's personal patterns** | `~/.claude/security-audit-personal.txt` | 🔴 Critical |
| **Generic PII** (emails, phone numbers) | ripgrep | 🟡 Warning |
| **Internal hostnames** (`*.internal`, `*.local`, `*.corp`) | ripgrep | 🟡 Warning |
| **Suspicious commit messages** (`remove secret`, `delete password`) | git log scan | 🟡 Warning |
| **Large binary files** (>5MB committed) | git ls-files | 🟡 Warning |
| **`.gitignore` coverage gaps** | template comparison | 🔵 Info |
| **OS cruft** (`.DS_Store`, `Thumbs.db`) | git ls-files | 🔵 Info |
| **Auth posture** (edge gate, phishing-resistant MFA, session hygiene) | Phase H heuristics | 🟡 Warning |

## Process

### 1. Dependency check

```bash
# gitleaks — primary secret scanner
which gitleaks >/dev/null 2>&1 || {
  echo "Installing gitleaks..."
  brew install gitleaks
}
```

If brew isn't available, fall back to manual pattern scanning (less coverage). Tell the user:

```
⚠️  gitleaks not installed. Falling back to regex-only scan (lower confidence).
    Install: brew install gitleaks
```

### 2. Resolve target

- If a path argument is given, `cd` into it. Otherwise use cwd.
- Verify it's a git repo: `git rev-parse --git-dir` — if not, abort with a clear message.
- Capture: `git rev-parse --show-toplevel`, current branch, `git remote -v`, total commits.

### 3. Phase A — Secret scan (gitleaks)

**Working tree:**
```bash
gitleaks detect --no-banner --redact --report-format json --report-path /tmp/gitleaks-tree.json --source .
```

**Git history** (skip if `--quick`):
```bash
gitleaks detect --no-banner --redact --report-format json --report-path /tmp/gitleaks-history.json --source . --log-opts="--all"
```

Parse JSON: count findings, group by rule (e.g. "AWS Access Key", "GitHub PAT"), capture file + line + redacted snippet. Never print the actual secret — `--redact` keeps it safe.

### 4. Phase B — Committed env files

```bash
git ls-files | grep -E '(^|/)\.env(\..+)?$' | grep -vE '\.env\.(example|template|sample)$'
```

Any hit = critical. Recommended fix:
```bash
git rm --cached .env
echo '.env' >> .gitignore
git commit -m "🔒 security: stop tracking .env"
# Then rotate any keys it contained, and use git-filter-repo to scrub from history
```

### 5. Phase C — Personal patterns

Look for the user's personal pattern file (in priority order):
1. `./.security-audit-personal.txt` (repo-local, gitignore it!)
2. `${CLAUDE_PLUGIN_DATA}/security-audit-personal.txt`
3. `~/.claude/security-audit-personal.txt`

Format: one pattern per line, `#` for comments. Each line is a ripgrep regex.

```
# Personal info — never share publicly
yourname@personal.com
\bJane Doe\b
\b\+1[-\s]?555[-\s]?\d{3}[-\s]?\d{4}\b
123 Main Street

# Work info
acmecorp\.com
\bACME Internal\b
project-codename-falcon
```

If no file exists, skip this phase silently and add a tip to the final report:

```
💡 Tip: Create ~/.claude/security-audit-personal.txt with patterns specific to you
   (real name, personal email, employer, internal project codenames) for stronger checks.
```

Run each pattern with ripgrep:
```bash
rg --no-heading --line-number --color=never -e "<pattern>" .
```

### 6. Phase D — Generic PII sweep

Two ripgrep passes against the working tree (skip `node_modules`, `.git`, `dist`, `build`, lockfiles):

**Emails** (excluding obvious examples):
```bash
rg --no-heading -n -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
   --glob '!*.lock' --glob '!*.lockb' --glob '!node_modules' --glob '!.git' \
   | grep -vE '@example\.(com|org)|@test\.com|@localhost|noreply@|@anthropic\.com'
```

**Phone numbers** (US/UK/EU formats):
```bash
rg --no-heading -n -e '\b(\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}\b'
```

Group results by file. Phone false-positive rate is high (matches version numbers, IDs) — present as "review these" not "fix these."

### 7. Phase E — Internal hostnames

```bash
rg --no-heading -n -e '\b[a-zA-Z0-9-]+\.(internal|local|corp|intranet|lan)\b'
```

### 8. Phase F — Risky git history

Suspicious commit messages — these often *are* the leak (someone removed a secret in a later commit, but it's still in history):

```bash
git log --all --oneline --grep -E -i 'secret|password|token|api[_-]?key|credential|leak|oops|whoops|remove key|delete key' \
  | head -30
```

Each match = "this commit may contain a secret in its diff — investigate with `git show <sha>`."

### 9. Phase G — Repo hygiene

**Tracked files that probably shouldn't be:**
```bash
git ls-files | grep -E '(\.DS_Store|Thumbs\.db|\.idea/|\.vscode/settings\.json|\.swp$|\.pyc$|__pycache__|\.log$)$'
```

**Large committed files (>5MB):**
```bash
git ls-files | xargs -I{} sh -c 'if [ -f "{}" ]; then size=$(wc -c <"{}"); if [ "$size" -gt 5242880 ]; then echo "${size} {}"; fi; fi' 2>/dev/null
```

**`.gitignore` coverage gaps** — check if these common entries are missing:
```
.env
.env.*
.DS_Store
node_modules/
__pycache__/
*.pyc
.idea/
.vscode/
*.log
dist/
build/
```
Show only the *missing* ones, not the present ones.

### 9a. Phase H — Auth posture

For any app with a sign-in (look for `clerk`, `better-auth`, `workos`, an `auth` route, or a session cookie), check it against the **authentication-hardening playbook** (`llm-wiki-security/wiki/playbooks/authentication-hardening.md`). Auth is the main attack surface once data is encrypted, so flag gaps:

```bash
# Is there a public login route on what looks like a single-user / internal app?
git ls-files | grep -iE 'routes/.*(sign-in|login|auth)' | head
# Any phishing-resistant factor wired? (passkey / webauthn / FIDO)
grep -rilE 'passkey|webauthn|fido2?' src 2>/dev/null | head
# SMS / TOTP-only MFA (NOT phishing-resistant) used as the second factor?
grep -rilE 'sms|twilio|totp|otp' src 2>/dev/null | head
# Long-lived / never-expiring sessions?
grep -rinE 'maxAge|expiresIn|session.*(ttl|expir)' src 2>/dev/null | head
```

Warn (not block) when:
- A single-user or internal app exposes a public login route instead of gating at the edge (Cloudflare Access + WARP). Recommend the edge-gate pattern.
- MFA is SMS/TOTP-only with no phishing-resistant option (passkey/FIDO2/WebAuthn). Recommend adding passkeys (NIST 800-63B AAL2+, CISA gold standard).
- Sessions are long-lived with no re-auth (step-up) before sensitive actions.
- Auth secrets/JWT-signing keys are not in a secret store.

Point the user at the playbook for the full standard rather than restating it here.

### 10. Report

Print a single structured report. Use this layout — terminal-friendly, no fluff:

```
🔒 Security Audit — <repo path>
   Branch: <branch> | Commits scanned: <n> | Mode: <full|quick>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 CRITICAL — fix before sharing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1] AWS Access Key in .env.production:3
    Detected by: gitleaks (rule: aws-access-token)
    Also in history: yes (commits: a3f2b1c, 9c4e2a1)
    Fix:
      1. Rotate this key in AWS console NOW (treat as compromised)
      2. git rm --cached .env.production && add to .gitignore
      3. Scrub history: git filter-repo --path .env.production --invert-paths
      4. Force-push (coordinate with team) and notify any forks

[2] Committed .env file: backend/.env
    Fix:
      1. Rotate any keys it contains
      2. git rm --cached backend/.env
      3. echo 'backend/.env' >> .gitignore
      4. Commit + scrub history (see above)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟡 WARNING — review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[3] Personal email found (3 occurrences):
    - README.md:42      (you@personal.com)
    - CONTRIBUTORS:1    (you@personal.com)
    - package.json:5    (you@personal.com)
    Fix: replace with a public alias or no-reply address.

[4] Internal hostname references (2):
    - docs/deploy.md:18 (db.acme.internal)
    - scripts/sync.sh:4  (api.acme.internal)
    Fix: replace with placeholders like <DB_HOST>.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔵 INFO — consider
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[5] .gitignore is missing common entries: .env, .DS_Store, dist/
[6] Large file committed: assets/demo.mov (47MB) — consider git-lfs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 2 critical · 2 warning · 2 info
Verdict: 🚫 NOT SAFE TO PUBLISH — fix critical issues first.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If zero critical findings:

```
Verdict: ✅ Safe to publish.
   (After addressing warnings if any contain info you don't want public.)
```

### 11. After the report

If critical findings exist, ask the user (via AskUserQuestion):

1. **Walk me through fixing them** — go finding-by-finding, generate the exact commands per file
2. **Just give me the commands** — print a single bash script they can run
3. **I'll handle it** — exit, leave them to it

For history scrubbing, always recommend [`git-filter-repo`](https://github.com/newren/git-filter-repo) over `git filter-branch` (deprecated). Warn that force-pushing rewritten history breaks anyone who has cloned/forked.

## Important Caveats

- **Rotate keys, don't just delete them.** A secret committed even briefly to a public repo must be considered compromised. The fix is rotation in the upstream system + history scrubbing — not just `git rm`.
- **gitleaks has false positives.** Test fixtures, mock keys, and example values can trip rules. Mark these with a `# gitleaks:allow` comment to whitelist legitimate cases.
- **The personal-patterns file is itself sensitive.** Don't commit it. Add `.security-audit-personal.txt` to your global `~/.gitignore_global`.
- **History scrub is dangerous and irreversible.** Make sure you have a backup clone before running `git filter-repo`. Force-pushing breaks open PRs and forks.
- **This skill is a safety net, not a guarantee.** A determined adversary with repo access (issues, PR comments, gh-pages, deploy logs) has more attack surface than the source tree. For genuinely sensitive repos, follow it up with a manual review.

## Personal Patterns File — Setup

First-time setup, suggest this to the user:

```bash
cat > ~/.claude/security-audit-personal.txt <<'EOF'
# Lines starting with # are comments. Each non-empty line is a ripgrep regex.
# Keep this file private — it itself contains the things you don't want public.

# Your personal contact info
your.personal@email.com
\b<Your Real Name>\b
\b\+\d{1,3}[-\s]?\d{3,4}[-\s]?\d{3,4}[-\s]?\d{3,4}\b

# Your employer / venture identifiers
yourcompany\.com
\b<Internal Codename>\b

# Sensitive customer / partner names
\b<Customer Name>\b
EOF
chmod 600 ~/.claude/security-audit-personal.txt
```

## Output for Programmatic Use

If invoked with `--json`, write the full report to `/tmp/security-audit-<timestamp>.json` and print only the path. Schema:

```json
{
  "repo": "/abs/path",
  "branch": "main",
  "scanned_at": "2026-04-19T14:32:00Z",
  "mode": "full",
  "findings": [
    {
      "severity": "critical",
      "category": "secret",
      "rule": "aws-access-token",
      "file": ".env.production",
      "line": 3,
      "in_history": true,
      "history_commits": ["a3f2b1c", "9c4e2a1"],
      "fix": ["Rotate key", "git rm --cached .env.production", "..."]
    }
  ],
  "summary": { "critical": 2, "warning": 2, "info": 2 },
  "verdict": "not_safe"
}
```

## See Also

- [git-guardrails](../git-guardrails/SKILL.md) — blocks destructive git commands at execution time
- [gitleaks](https://github.com/gitleaks/gitleaks) — upstream secret scanner
- [git-filter-repo](https://github.com/newren/git-filter-repo) — modern history rewriter
