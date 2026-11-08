---
description: Run tests, uv and pnpm through scripts/dev/with-tmp-layout so temp files land under TMPDIR/project/branch/tool
alwaysApply: true
---

# Temp files follow the layout

Temp files from test runs, `uv` and `pnpm` go under `$TMPDIR/<project>/<branch>/<tool>` (a detached HEAD uses `detached-head/<sha>`), never loose at the `$TMPDIR` root. `scripts/dev/with-tmp-layout` sets that up (repository-helpers#832).

## What to do

1. Run `scripts/dev/pre-pr-checks` and `scripts/dev/run-tests`: they already use the layout.
2. For any other `uv`, `pnpm` or `pytest` command you run by hand, wrap it: `scripts/dev/with-tmp-layout <tool> -- <command>` (`--help` lists the tools and options). In a consumer repo use `"${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/dev/with-tmp-layout"`, and let the repo's own `.github/ci` wrappers do it when they exist.
3. Pick one store per `node_modules`: pnpm 10 asks to purge it when the store changes and fails without a TTY, so do not switch an existing `node_modules` between the layout store and another one (remove `node_modules` first if you must).
4. Do not delete the layout directories by hand. A passing test run removes its own run directory, a failing one keeps it for inspection, the uv and pnpm caches stay, and the harness sweeps anything older than 3 days.

## CI

Workflows add the composite action `the-hcma/repository-helpers/actions/setup-tmp-layout@<full SHA on main>` before the first step that runs `uv`, `pnpm` or `pytest`, and the `.github/ci` wrappers re-exec themselves through `with-tmp-layout`. `scripts/github-repo-lint` fails a repo that does not (see the "Temp layout CI" row in `AGENTS.md`).
