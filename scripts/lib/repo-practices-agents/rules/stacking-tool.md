---
description: Choose Graphite vs GitHub Stacked PRs from .github/stacking-tool
alwaysApply: true
---

# Stacking tool preference

Before creating branches or submitting/restacking PRs, **read** `.github/stacking-tool`
(single line: `graphite` or `gh-stack`). Missing or invalid values: **stop and ask** —
do not guess.

<!-- stacking-tool-canonical-graphite-skill: @@STACKING_TOOL_GRAPHITE_SKILL_URL@@ -->
<!-- stacking-tool-canonical-gh-stack-skill: @@STACKING_TOOL_GH_STACK_SKILL_URL@@ -->

Canonical skills live in **repository-helpers** (not copied into this repo):

- **Graphite:** @@STACKING_TOOL_GRAPHITE_SKILL_URL@@
- **gh-stack:** @@STACKING_TOOL_GH_STACK_SKILL_URL@@

Local clone (when `${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}` is synced):

- `${REPOSITORY_HELPERS_DIR}/.agents/skills/graphite/SKILL.md`
- `${REPOSITORY_HELPERS_DIR}/.agents/skills/gh-stack/SKILL.md`

## `graphite`

- Follow the Graphite skill above (`gt create` / `gt submit` / `gt restack`).
- Prefer repository-helpers `scripts/dev/submit-stack` when available in that clone.

## `gh-stack`

- Follow the gh-stack skill (non-interactive: `view --json`, `submit --auto --open`,
  named `init`/`add`).
- Prefer repository-helpers `scripts/dev/submit-stack` / `scripts/dev/ship-and-review`
  when available (they dispatch via `scripts/lib/stacking-tool`).
- **Do not** mix with `gt create` / `gt submit` / `gt restack` on the same stack.

## Marker cutover checklist

When flipping `.github/stacking-tool` (or landing an MQ/`gh-stack` cutover PR):

1. Update `AGENTS.md` stacking/merge guidance to match the new marker (and GitHub
   auto-merge: `gh pr merge --auto --squash` — not `merge-it`).
2. Rewrite `.agents/rules/pr-ship-and-review.md` submit block to the marker-aware
   template in `scripts/lib/repo-practices-agents/rules/pr-ship-and-review.md`
   (or ensure it documents both backends gated on the marker; keep a thin
   `.cursor/rules/pr-ship-and-review.mdc` shim).
3. Delete root `GRAPHITE.md` when switching to `gh-stack` (canonical skill lives in
   repository-helpers).
4. Keep `.agents/rules/stacking-tool.md` (+ Cursor shim) in sync with the consumer
   template.
5. Re-run `scripts/github-repo-lint --repo OWNER/NAME --suggest --strict-onboarding`
   and fix stacking-docs consistency findings.

## Unchanged regardless of marker

Agent review, CI wait, and reply-before-resolve still follow
`.agents/rules/pr-ship-and-review.md` and the canonical ship-and-review skill in
repository-helpers.
