---
name: spec-to-repo
description: Graduate an accepted vault spec into a fresh repo. Reads the spec, scaffolds the repo (delegates to a stack skill or stamps a minimal layout), copies the spec into docs/specs/, derives .ralph/prd.json from the User Stories section, and cross-links the vault entry. Closes the loop between research-in-vault and implementation-in-repo. Use when an accepted vault-genesis spec is ready to become code.
category: development
argument-hint: [--scaffold tanstack|minimal|none] [--target <repo-path>] [--name <repo-name>] <vault-spec-path>
allowed-tools: Read Write Edit Glob Grep Bash AskUserQuestion
content-pipeline:
  - pipeline:input
  - platform:agnostic
  - role:rules
---

# Spec to Repo

Graduates a vault-genesis spec into a working repo. After this runs, the repo has the spec next to its code, a Ralph-ready PRD derived from the spec's stories, and a cross-link back to the vault genesis snapshot.

Sister skills: `/generate-spec` (produces the vault input), `/compare-specs` (diffs versions), `/compare-codebase-to-spec` (audits drift), `/ralph` (consumes the derived PRD).

## Usage

```
# Minimal scaffold (git init + docs/ + .ralph/, no stack opinions)
/spec-to-repo --scaffold minimal --target ~/Dev/ai-projects/myapp <vault-spec-path>

# TanStack Start + Cloudflare Workers stack (delegates to /ro:new-tanstack-app)
/spec-to-repo --scaffold tanstack --target ~/Dev/ai-projects/myapp <vault-spec-path>

# Repo already exists, just copy spec and derive PRD
/spec-to-repo --scaffold none --target ~/Dev/existing/myapp <vault-spec-path>
```

If `--target` is omitted, default to `~/Dev/ai-projects/<name>` where `<name>` is from `--name` flag, the spec frontmatter `title`, or kebab-cased prompt.

If `--scaffold` is omitted, ask via AskUserQuestion. Default recommendation is `tanstack` for web/SaaS specs, `minimal` for everything else.

## Procedure

### Step 0 — Pre-flight (catch credential + access issues BEFORE scaffolding)

Run these checks in order. If any fails, surface the exact problem and stop. Do NOT silently work around credential failures (the night-shift Dataforce run on 2026-05-06 worked around a revoked Cloudflare token by adding `continue-on-error: true` to CI; that's exactly what this pre-flight prevents).

| Check | Command | Pass condition |
|---|---|---|
| `gh` is authenticated | `gh auth status` | "Logged in to github.com account ..." |
| Target GitHub org exists and the user is a member | `gh api /user/orgs --jq '.[].login'` then check the spec's stated org appears in the list | Org login matches spec's `repo` field (case-sensitive on GitHub) |
| `wrangler` is installed and auth works | `wrangler whoami` | Returns email + account list, NOT "You are not authenticated" |
| Cloudflare token in env actually works | `curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \| jq .success` | `true` |
| Cloudflare account ID matches | `curl -s "https://api.cloudflare.com/client/v4/accounts" -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \| jq .result[0].id` matches `$CLOUDFLARE_ACCOUNT_ID` | exact match |
| `pnpm` + `node` + `git` versions | `pnpm -v && node -v && git --version` | All present, node 20+ |
| Spec env vars all populated | for each env var listed in the spec's GitHub Actions secrets table, check it's set in `~/.claude/.env.<context>` and not empty | All set |

Report the pre-flight as a table to the user. If anything fails, include the EXACT remediation (e.g. "mint a fresh CF token at https://dash.cloudflare.com/profile/api-tokens with scopes X / Y / Z").

This pre-flight takes ~30 seconds and catches the night-shift class of problem before kicking off hours of work.

### Step 1 — Validate the spec

Read the vault spec. Confirm:

- Frontmatter has `status: accepted`. If `status: draft` or anything else, ask via AskUserQuestion: "Spec status is `<status>`. Graduate anyway?" Default no.
- Frontmatter `repo` is empty or unset. If already populated, this spec has already graduated; surface the existing repo path and ask whether to abort, re-graduate to a new repo, or refresh the derived PRD only.
- Frontmatter's stated GitHub org matches one the user belongs to (case-sensitive, e.g. `Simplicity-Labs` not `simplicitylabs`). The night-shift run nearly used the wrong org name because the spec used the lowercase form; pre-flight (step 0) catches this.
- The User Stories section parses (US-NNN headings with EARS-format acceptance tables). If not, surface the parse error and stop; the spec is not ready.

### Step 2 — Resolve the target repo

- If `--target` exists and is non-empty: ask "Target `<path>` exists and contains files. Continue?" Show top-level `ls` for context. Default no.
- If `--target` doesn't exist: create the parent directory if needed.
- Resolve repo name: `--name` flag, then spec `title` slug, then prompt.

### Step 3 — Scaffold

Branch on `--scaffold`:

**`tanstack`**: Invoke `/ro:new-tanstack-app --target <path> --name <name>` and let it run its own decisions (DB, auth, observability). Wait for it to finish before continuing.

**`minimal`**: Stamp this layout:

```
<target>/
├── .gitignore         (node, dist, .ralph/archive, .env, .dev.vars)
├── README.md          (one paragraph from spec Outcomes section + link to spec)
├── docs/
│   └── specs/         (created, empty for now; spec lands here in step 4)
├── .ralph/            (created, empty for now; prd.json lands here in step 5)
└── .gitkeep markers in docs/, .ralph/
```

Then `git init`, `git add -A`, initial commit:
```
🌱 chore: scaffold repo from vault spec <vault-short>:<filename>
```

**`none`**: Skip scaffolding. Confirm `<target>` is a git repo; if not, abort with a clear message.

### Step 4 — Copy spec into the repo

Copy the vault spec markdown file to `<repo>/docs/specs/<basename>` (preserve filename: e.g. `myapp-spec-v1-fresh-2026-05-02.md` becomes `spec-v1-fresh-2026-05-02.md` in the repo, dropping the project-name prefix since the repo identity is implicit).

Update the **repo copy's** frontmatter:

| Field | Value |
|---|---|
| `repo` | repo URL (from `git remote get-url origin` if set) or absolute path |
| `graduated-from-vault` | `<vault-short>:<original vault path>` |
| `status` | `accepted` (preserved) |
| `date` | preserved (this is the genesis date, not graduation date) |
| `version` | `v1` (preserved) |

Do not edit the body. The spec is the same artefact, just relocated.

### Step 5 — Derive `.ralph/prd.json`

Parse the spec's `## 5. User Stories` section. For each `### US-NNN — <title>` block:

| Spec field | PRD field | How to map |
|---|---|---|
| `### US-NNN — <title>` | `id`, `title` | direct |
| "As a X, I want Y, so that Z" line | `description` | direct |
| Each row of the EARS table | one entry in `acceptanceCriteria` | format as `WHEN <trigger> THE system SHALL <behaviour>` (preserve existing wording) |
| Order in spec (top to bottom) | `priority` | 1, 2, 3, ... |
| `### 8. Plan` milestone for the story | (notes) | optional: prefix `notes` with `M<n>: <milestone goal>` |

Write to `<repo>/.ralph/prd.json`:

```json
{
  "project": "<repo-name>",
  "branchName": "ralph/v1-genesis",
  "description": "<one-paragraph summary from spec § Outcomes>",
  "spec": "docs/specs/<basename>",
  "userStories": [
    {
      "id": "US-001",
      "title": "...",
      "description": "As a ..., I want ..., so that ...",
      "acceptanceCriteria": [
        "WHEN ... THE system SHALL ...",
        "WHEN ... THE system SHALL ..."
      ],
      "priority": 1,
      "passes": false,
      "notes": "M1 (tracer): <milestone goal>"
    }
  ]
}
```

The `spec` field is new and points at the in-repo spec path; future Ralph runs and audits use it as the source-of-truth pointer.

### Step 6 — Update the vault spec

Open the **original vault spec** and update frontmatter:

| Field | New value |
|---|---|
| `status` | `graduated-to-repo` |
| `repo` | the same repo URL/path used in step 4 |

At the bottom of the body, add (or update if it exists) a single line:

```
> Graduated to repo: [<repo-name>:docs/specs/<basename>](file://<absolute-path>) on YYYY-MM-DD.
```

If the vault has cross-vault link conventions (it does for llm-wiki), use the obsidian:// URL form when the repo is itself in a known location, otherwise a plain `file://` link is fine.

### Step 7 — Commit on the repo side

In the new repo, commit steps 4-5 as one change:

```
✨ feat(spec): graduate v1 genesis spec from vault and derive Ralph PRD
```

Use the user's normal commit conventions (emoji + conventional format, no Co-Authored-By).

### Step 8 — Open

Run, in this order:

1. `open <repo>` (Finder) so the user can see the layout.
2. Open the in-repo spec in the editor: `open -a "Visual Studio Code" <repo>/docs/specs/<basename>` or whatever the user's editor is. If unsure, just print the path.
3. Open the original vault spec via `obsidian://open?vault=llm-wiki-<vault-short>&file=<url-encoded-path-without-.md>` so the user can verify the cross-link.

### Step 9 — Print a summary

Print a 5-line summary:

```
✅ Spec graduated.
   vault: <vault-spec-path>  (status: graduated-to-repo)
   repo:  <repo-path>
   spec:  <repo>/docs/specs/<basename>
   PRD:   <repo>/.ralph/prd.json (<N> stories, priority 1 = US-001 "<title>")

Next: run /ralph in <repo> to start the tracer-bullet implementation.
```

## Edge cases and rules

- **Already-graduated spec**: refuse to overwrite. Offer to refresh `.ralph/prd.json` only (skipping repo scaffold + spec copy).
- **Multiple repos sharing one spec**: don't try to handle this. Treat as a misuse case; ask the user to clarify.
- **Empty User Stories section**: refuse. A spec without stories cannot derive a PRD; tell the user to add stories before graduating.
- **EARS rows that aren't in EARS form**: pass them through verbatim and flag a single warning at the end ("3 acceptance criteria are not in EARS form; consider tightening for testability").
- **Repo name collision** with `~/Dev/ai-projects/<existing>`: don't auto-suffix. Ask explicitly.
- **No `git` available**: surface and stop. Do not attempt fallback.
- **Pre-flight failure**: NEVER silently work around. If `wrangler whoami` fails, stop and ask the user to mint a fresh token. If org membership check fails, stop and ask the user to confirm the org name. The autonomous loop must not start with broken credentials; the night-shift Dataforce run shipped CI-green-but-not-actually-deployed code because pre-flight didn't catch a revoked CF token.
- **GitHub org plan limits**: if the target org is on the free plan and the repo will be private, **branch protection with required-status-checks is not available** (HTTP 403 from `gh api`). Detect this in pre-flight via `gh api /orgs/<org> --jq '.plan.name'` and surface to the user: "The Simplicity-Labs org is on the free plan; branch protection on private repos requires GitHub Team ($4/user/month). Continue with soft enforcement (auto-merge + squash-only + delete-on-merge), or upgrade first?"

## Style rules for any output

- No em-dashes or en-dashes in any markdown produced.
- Commit messages use the user's emoji conventional format.
- Do not add `Co-Authored-By` lines (the user has explicitly asked for this in CLAUDE.md).
- Keep the PRD `description` field one paragraph; longer summaries belong in the spec, not the PRD.

## What this skill does NOT do

- It does not run the implementation. That's `/ralph`.
- It does not deploy. That's `/ro:cf-ship` or `/ro:fly-deploy`.
- It does not generate tests. Tests are derived as part of implementing each story.
- It does not maintain ongoing sync between the vault and repo specs after graduation. The repo is canonical from this point; the vault is a frozen genesis snapshot.
