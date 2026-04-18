---
name: write-a-prd
description: Generate a PRD through an interactive interview. Quick mode writes prd.json directly, plan mode creates a reviewable plan.md first. Use when user wants to write a PRD, plan a feature, create user stories, or start a Ralph project.
category: development
argument-hint: [--quick | --plan] <feature-name>
allowed-tools: Read Write Edit Glob Grep
---

# Write a PRD

Interactive interview that produces a `.ralph/prd.json` ready for the Ralph loop.

## Usage

```
/write-a-prd --quick my-feature    # Fast: interview -> prd.json
/write-a-prd --plan my-feature     # Thorough: interview -> plan.md -> review -> prd.json
/write-a-prd my-feature            # Defaults to --quick
```

## --quick Mode

### Step 1: Interview (5-8 questions via AskUserQuestion)

Ask these in order, one at a time. Adapt follow-ups based on answers.

1. **What** — "Describe the feature in 1-2 sentences. What does it do?"
2. **Why** — "What problem does this solve? What's the motivation?"
3. **Who** — "Who uses this? (developer, end-user, CLI user, automated system)"
4. **Scope** — "What's explicitly OUT of scope for this feature?"
5. **Acceptance** — "How do we know it's done? List the key acceptance criteria."
6. **Dependencies** — "Does this depend on anything existing? (files, APIs, libraries, other features)"
7. **Constraints** — "Any technical constraints or conventions to follow?" (skip if the user already covered this)
8. **Priority** — "What should be built first? Any ordering dependencies between pieces?"

### Step 2: Generate prd.json

Create `.ralph/prd.json` (create `.ralph/` directory if needed):

```json
{
  "project": "<project-name from package.json or directory name>",
  "branchName": "ralph/<feature-name>",
  "description": "<feature description from interview>",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short story title",
      "description": "As a <who>, I want <what> so that <why>",
      "acceptanceCriteria": [
        "Criterion from interview",
        "Another criterion"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Step 3: Review

Show the generated PRD to the user. Ask: "Does this look right? Any stories to add, remove, or reorder?"

Apply changes if requested, then confirm the final version.

## --plan Mode

### Step 1: Extended Interview (8-12 questions via AskUserQuestion)

Same questions as quick mode, plus:

9. **Architecture** — "How should this be structured? Any patterns to follow or avoid?"
10. **Risks** — "What could go wrong? What are you uncertain about?"
11. **Phases** — "Should this be delivered in phases? Any natural breakpoints?"
12. **Open questions** — "Anything you're unsure about that needs investigation first?"

### Step 2: Generate plan.md

Create `plans/<feature-name>.md` (create `plans/` directory if needed) with these sections:

- **Problem Statement** — why this feature exists
- **Proposed Solution** — high-level approach
- **Architecture Decisions** — key technical choices and rationale
- **Phases** — each phase has a goal and stories. Phase 1 is always the tracer bullet (thinnest end-to-end slice).
- **Risk Assessment** — table with Risk, Likelihood, Impact, Mitigation columns
- **Open Questions** — checklist of unknowns needing investigation

### Step 3: Review Loop

Present the plan. Ask: "Review this plan. What would you change?" Iterate until the user approves (possibly multiple rounds), then proceed.

### Step 4: Convert to prd.json

Convert the approved plan into `.ralph/prd.json` using the same format as quick mode. Flatten all phases into a single ordered story list, preserving priority order. Confirm: "Plan converted to `.ralph/prd.json` — ready for `/ralph`."

## Story Writing Rules

- **Vertical slices, not horizontal layers.** Each story cuts through UI, logic, and data. Never a story like "set up database" alone.
- **Independently demoable.** After each story, you can show something working.
- **Tracer bullet first.** The first story should be the thinnest possible end-to-end path.
- **Foundational/risky slices first.** Validate unknowns early, not last.
- **One Ralph iteration per story.** If a story feels too big for one context window, split it.
- **Use "As a X, I want Y so that Z" format** for story descriptions.
- **IDs are sequential:** US-001, US-002, US-003, etc.
- **Priority matches order:** story with priority 1 is built first.
