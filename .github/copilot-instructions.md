# Copilot Instructions

> Full coding standards, conventions, and CI requirements are in [AGENTS.md](../AGENTS.md).
> Graphite workflow reference is in [GRAPHITE.md](../GRAPHITE.md).
> PR ship and agent review loop: [`.cursor/rules/pr-ship-and-review.mdc`](../.cursor/rules/pr-ship-and-review.mdc).

## Starting New Work

**Always begin a session by running:**

```bash
scripts/dev/start-development --worktree <stack-name> --no-interactive
cd .worktrees/<stack-name>-wt
```

This is the single entry point for new work. It prunes stale worktrees, syncs Graphite,
and creates or resumes a stack worktree. Do not manually run `gt sync`, create worktrees,
or implement on the primary clone (`main` worktree).

## Key Rules (Quick Reference)

- Scripts → `scripts/`; tests → `tests/`; no `.sh` extensions.
- Every script: `#!/usr/bin/env bash` + `set -euo pipefail`.
- External commands in `scripts/*` must use `scripts/lib/runner` helpers (see AGENTS.md).
- `shellcheck -S info` must report zero findings. No suppressions without an explanatory comment.
- Declare `local` / `readonly` separately from command substitutions (SC2155).
- Never declare `local -r` inside a loop body.
- Every behaviour change or bug fix must have a test in `tests/`.
- Never push directly to `main`. Use `gt create` → `scripts/dev/submit-stack`.
- To merge a PR: `gh pr edit <number> --add-label merge-it`. Never `gh pr merge`.

## Submit and ship

```bash
scripts/dev/pre-pr-checks
scripts/dev/submit-stack                    # or scripts/dev/ship-and-review
scripts/dev/post-pr-submission-checks --pr <n>   # after each push if not using submit-stack
scripts/wait-for-agent-review loop --pr <n>      # when CI is green
```

The agent review loop uses **dual timeouts**: **15m** idle-success after all feedback
is addressed (any party), **12h** cap when review cycles never converge. Reply on-thread
before resolving agent threads (exit **3** if missing). See `etc/agent-review.env.example`.
