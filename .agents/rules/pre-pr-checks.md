---
description: Block PR submit until pre-pr-checks pass (shellcheck, tests, clean main wt)
alwaysApply: true
---

# Pre-PR checks (required)

Before **`gt submit`** or opening a PR in this repository:

1. Run **`scripts/dev/pre-pr-checks`** from the feature worktree (must exit 0).
   - Prefer **`scripts/dev/submit-stack`** instead of bare `gt submit` (runs checks, then `gt submit --publish --no-interactive`).

2. Do **not** submit if pre-pr-checks failed or was skipped (including missing `shellcheck`,
   `rg`, failing `tests/*.test`, or a failing **secret-scan** when that job is planned).
   Escape hatch only: `PRE_PR_CHECKS_SKIP=job1,job2` (e.g. `secret-scan`).

3. In the PR **Test plan**, note that `scripts/dev/pre-pr-checks` passed (or paste the final `==> pre-pr-checks passed` line).

4. Scripts must not leave changes on the **primary (main) worktree**; pre-pr-checks verifies that automatically.

Bare `gt submit` without a successful pre-pr-checks run is not acceptable unless the user explicitly overrides.

## Apply formatters before check (required)

`pre-pr-checks` is **check-only** by default (e.g. `ruff format --check`, `cargo fmt -- --check`).
After review-fix edits — especially string literals — **apply** formatters first, then run the gate:

```bash
# Python (match CI paths; adjust for the repo)
uv run ruff format .
# Rust
cargo fmt --all
# Then the gate
scripts/dev/pre-pr-checks
# Or apply + check in one shot (mutates the worktree):
scripts/dev/pre-pr-checks --fix
```

Commit any format-only diff before `submit-stack`. Do **not** treat a green `pytest` /
`ruff check` / partial job as a pre-PR pass.

## No truncated pre-PR output

Do **not** pipe `pre-pr-checks` to `tail` / `head`. Require exit **0** and the final
`==> pre-pr-checks passed` line from the full run.

```bash
# ❌ Truncated — hides failures above the last few lines
scripts/dev/pre-pr-checks 2>&1 | tail -8

# ✅ Full output + exit status
scripts/dev/pre-pr-checks
```

## No partial shellcheck (CI scope)

CI runs **`shellcheck -S info`** on **all** of:

- `scripts/*`, `scripts/dev/*`, `scripts/lib/*`, `scripts/lib/*/*` (nested libs like
  `agent-review-profiles/`; non-script suffixes such as `.snippet` / `.yml` filtered out)
- `tests/*`, `tests/lib/*` — including `tests/*.test` harness files

Do **not** treat “I shellchecked the script I edited” as a substitute for `pre-pr-checks`. A green `shellcheck scripts/dep-updater` does **not** cover test-file findings (e.g. SC2016 in `tests/dep-updater.test`).

The version is **pinned** via `scripts/lib/ci-shellcheck` (CI and `pre-pr-checks` install the same SHA-256-verified release binary), so local and CI findings agree. Do not lint with an ad-hoc `shellcheck` off `PATH` — run `pre-pr-checks`. `scripts/github-repo-lint` warns when the pin (`ci_shellcheck_version` / `ci_shellcheck_sha256`) falls behind the newest release-age-eligible shellcheck — bump both, then re-sync any consumer `.github/ci/shellcheck`.

```bash
# ❌ Incomplete — misses tests/*.test
shellcheck scripts/dep-updater

# ✅ Matches CI
scripts/dev/pre-pr-checks
```

When adding static assertions in `tests/*.test` that grep for literal `$var` strings in source under test, add `# shellcheck disable=SC2016` with a one-line reason (see existing patterns in `tests/dep-updater.test`).
