# Copilot Instructions

> Full coding standards, conventions, and CI requirements are in [AGENTS.md](../AGENTS.md).
> Graphite workflow reference is in [GRAPHITE.md](../GRAPHITE.md).

## Starting New Work

**Always begin a session by running:**

```bash
scripts/dev/start-development
```

This is the single entry point for all new work. It prunes stale worktrees, syncs Graphite, and creates or resumes a worktree. Do not manually run `gt sync`, create worktrees, or start coding directly on `main`.

## Key Rules (Quick Reference)

- Scripts → `scripts/`; tests → `tests/`; no `.sh` extensions.
- Every script: `#!/usr/bin/env bash` + `set -euo pipefail`.
- `shellcheck -S info` must report zero findings. No suppressions without an explanatory comment.
- Declare `local` / `readonly` separately from command substitutions (SC2155).
- Never declare `local -r` inside a loop body.
- Every behaviour change or bug fix must have a test in `tests/`.
- Never push directly to `main`. Use `gt create` → `gt submit --no-interactive`.
- To merge a PR: `gh pr edit <number> --add-label merge-it`. Never `gh pr merge`.
