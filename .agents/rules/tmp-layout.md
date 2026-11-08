---
description: Run tests, uv and pnpm through scripts/dev/with-tmp-layout so temp files land under TMPDIR/project/branch/tool
alwaysApply: true
---

# Temp files follow the layout

Temp files from test runs, `uv` and `pnpm` go under `$TMPDIR/<project>/<branch>/<tool>` (a detached HEAD uses `detached-head/<sha>`), never loose at the `$TMPDIR` root. `scripts/dev/with-tmp-layout` sets that up (repository-helpers#832).

## What to do

1. Run `scripts/dev/pre-pr-checks` and `scripts/dev/run-tests`: in this repository they already use the layout. In a consumer repo, `pre-pr-checks` runs the repo's own `.github/ci` wrappers (such as `pytest-hermetic`), and those wrappers must re-exec themselves through `with-tmp-layout` (the `github-repo-lint` check enforces that), so a wrapper that runs pytest outside the layout is a bug in that repo.
2. For any other `uv`, `pnpm` or `pytest` command you run by hand, wrap it: `scripts/dev/with-tmp-layout <tool> -- <command>` (`--help` lists the tools and options). `uv run pytest` needs both layers, nested: `scripts/dev/with-tmp-layout uv -- scripts/dev/with-tmp-layout pytest -- uv run pytest` (the `uv` layer sets the cache, the `pytest` layer sets pytest's `--basetemp`). A test script you run directly (`bash tests/<name>.test`, any other runner) is wrapped the same way, and it should create its own temp files under `$TMP_LAYOUT_DIR`, which the wrapper exports: until repository-helpers#840 lands the wrapper does not change `TMPDIR`, so plain `mktemp` output is not covered. In a consumer repo use `"${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/dev/with-tmp-layout"`, and let the repo's own `.github/ci` wrappers do it when they exist.
3. Pick one store per `node_modules`: pnpm 10 asks to purge it when the store changes and fails without a TTY, so do not switch an existing `node_modules` between the layout store and another one (remove `node_modules` first if you must).
4. Do not delete the layout directories by hand. A passing test run removes its own run directory, a failing one keeps it for inspection, the uv and pnpm caches stay, and the harness sweeps anything older than 3 days.

## CI

Workflows add the composite action `the-hcma/repository-helpers/actions/setup-tmp-layout@<full SHA on main>` in **each job** that runs `uv`, `pnpm` or `pytest`, before its first such step (every job gets its own runner, so a step in another job does not configure it), and the `.github/ci` wrappers re-exec themselves through `with-tmp-layout`. A workflow that runs one of those tools inline in a `run:` step must wrap that command too (`"$REPOSITORY_HELPERS_DIR/scripts/dev/with-tmp-layout" <tool> -- <command>`), because the action only exports the helper's location. `scripts/github-repo-lint` fails a repo whose workflows do not (see the "Temp layout CI" row in `AGENTS.md`); both of its checks (the action is present, `with-tmp-layout` is used) look at the workflow as a whole, not job by job or command by command, so check each job and each inline command yourself.
