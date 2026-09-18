---
description: Choose Graphite vs GitHub Stacked PRs from .github/stacking-tool
alwaysApply: true
---

# Stacking tool preference

Before creating branches or submitting/restacking PRs, **read** `.github/stacking-tool`
(single line: `graphite` or `gh-stack`). Missing or invalid values: **stop and ask** —
do not guess.

## `gh-stack` (this repo trial)

- Follow `.agents/skills/gh-stack/SKILL.md` (non-interactive flags: `view --json`,
  `submit --auto --open`, named `init`/`add`).
- Prefer `scripts/dev/submit-stack` / `scripts/dev/ship-and-review` (they dispatch via
  `scripts/lib/stacking-tool`).
- **Do not** mix with `gt create` / `gt submit` / `gt restack` on the same stack.

## `graphite`

- Follow `.agents/skills/graphite/SKILL.md` and the Graphite flow in
  `.agents/rules/pr-workflow.md` (`gt`, `scripts/dev/submit-stack`).

## Marker cutover checklist

When flipping `.github/stacking-tool` (or landing an MQ/`gh-stack` cutover PR) in a
**consumer** repo:

1. Update `AGENTS.md` stacking/merge guidance to match the new marker (GitHub auto-merge:
   `gh pr merge --auto --squash` — not `merge-it`).
2. Rewrite `.agents/rules/pr-ship-and-review.md` submit block to the marker-aware
   template under `scripts/lib/repo-practices-agents/rules/pr-ship-and-review.md`
   (plus thin `.cursor/rules/pr-ship-and-review.mdc` shim).
3. Delete root `GRAPHITE.md` when switching to `gh-stack` (skills here are SSOT).
4. Keep `.agents/rules/stacking-tool.md` (+ Cursor shim) aligned with the consumer
   stacking-tool template.
5. Run `scripts/github-repo-lint --repo OWNER/NAME --suggest --strict-onboarding` and fix
   stacking-docs consistency findings.

This repo keeps dual skills (graphite + gh-stack) on purpose; consumers should not.

## Unchanged regardless of marker

Agent review, CI wait, and reply-before-resolve still follow
`.agents/rules/pr-ship-and-review.md` / `.agents/skills/ship-and-review/SKILL.md`.
