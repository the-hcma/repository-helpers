---
description: CodeRabbit CLI skills are installed user-level with coderabbit skills; the review run caps and the no-credits rule stay in force
alwaysApply: true
---

# CodeRabbit CLI skills

The CodeRabbit CLI (0.9.1 and later) ships agent skills: `code-review`, `autofix` and `coderabbit-config` (upstream: https://github.com/coderabbitai/skills, docs: https://docs.coderabbit.ai/cli/skills). Install and update them at **user level** with `coderabbit skills`, never as copied skill bodies committed to a repository: the CLI verifies the release checksums, shows every destination path and asks for confirmation (default No).

## Installing and updating

1. Run `coderabbit skills --agent` (or `coderabbit skills update --agent`) to preview the plan. Under an agent the command only previews.

2. Show the plan to the user. Run the exact `action_required` command, which carries `--confirm <plan-hash>`, only after the user approves. A hash from one preview does not confirm another subcommand or a changed plan.

3. Installing, updating and uninstalling need no authentication. Running a review does: `coderabbit auth login` is the operator's step, and no token is ever pasted into a log, PR or commit (`.agents/rules/no-secret-exposure.md`).

4. Skills the official Claude Code or Codex plugin installed are never replaced by `coderabbit skills`; update those through the plugin marketplace.

## What each skill may do here

- **Pre-push review:** run `scripts/dev/coderabbit-cli-review`, normally as the `coderabbit-cli` job of `scripts/dev/pre-pr-checks`, not the `code-review` skill. That script owns the run caps (each head once, at most 2 heads per branch) and the allowance rule; a skill invocation must not bypass them. Never pass `--use-credits`.

- **`autofix`:** use it only inside the PR review loop (`.agents/skills/ship-and-review/SKILL.md`). Reply on every thread before resolving it, exactly as for any other review feedback, and let `scripts/dev/post-pr-submission-checks` and the loop gate the push. Its own push prompt is not an approval to merge.

- **`coderabbit-config`:** use it to create, update or validate `.coderabbit.yaml`. Validation changes no file; a save needs the user's approval of the preview, and the result goes through a normal PR.

## Why this is a user-level, breadcrumb-only rule

The skills overlap with the repository-owned review flow, so the repository keeps the policy (caps, credits, triage order) and leaves the skill content to the CLI. Consumer repositories carry a thin pointer to this canonical rule, not a copy of the skills (repository-helpers#860).
