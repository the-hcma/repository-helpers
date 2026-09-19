---
description: One combined Python lint/format/typecheck CI job per repo (ruff + pyright/mypy)
alwaysApply: false
globs: ["**/.github/workflows/*.yml", "**/.github/ci/*"]
---

# Python static checks belong in one CI job

Org Python repos (a `pyproject.toml` that lints with **ruff**) must run **ruff
check**, **ruff format --check**, and their typechecker (**pyright** or **mypy**)
in a **single** CI job named **`Python lint & format checks`**, driven by a shared
**`.github/ci/python-static`** wrapper script.

Do **not** split these into per-tool jobs (`Ruff`, `Pyright`, `Mypy`, `Backend
Lint`, …). Splitting:

- burns an extra runner and an extra `uv sync` per tool (same deps, same checkout);
- adds a **branch-protection required-status context per tool**, so adding a tool
  (e.g. a new `Ruff` job) silently drifts protection out of sync until someone
  runs `github-repo-lint --apply-fix` (the real-world `domesti-bot` "missing Ruff"
  failure).

## Do

Wrapper `.github/ci/python-static` (one `uv sync`, then all static checks):

```bash
#!/usr/bin/env bash
set -euo pipefail
bash .github/ci/setup-python
uv run ruff check <paths>
uv run ruff format --check <paths>
uv run pyright   # or: uv run mypy <paths>
```

`ci.yml` job:

```yaml
  python-static:
    name: Python lint & format checks
    needs: guard
    if: needs.guard.outputs.skip != 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7.0.1
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
      - uses: astral-sh/setup-uv@v8.3.1
        with:
          version: latest
      - name: Python lint & format checks
        run: bash .github/ci/python-static
```

Keep heavier / orthogonal jobs separate (pytest, browser tests, web build,
shellcheck, secret-scan) — only the cheap shared-venv Python static checks are
consolidated.

## Do not

- Add standalone `Ruff` / `Pyright` / `Mypy` / `Backend Lint` jobs.
- Publish those legacy names from **other** workflows via a parallel no-op
  (e.g. release-please matrix `script: .github/ci/cutover-ok`) or a
  `checks-action` conclusion that is not derived from `steps.*.outcome`.
- Inline the ruff/typecheck steps directly in `ci.yml` without the
  `.github/ci/python-static` wrapper (breaks local `pre-pr` reuse and drifts from
  the audit).
- Rename the job away from `Python lint & format checks` (it is the required
  branch-protection status context).

## Cutover

When migrating a repo that currently splits these jobs, keep temporary **alias**
jobs matching the old required contexts until branch protection is retargeted
(`github-repo-lint --repo OWNER/NAME --apply-fix`), then remove the aliases in a
follow-up PR.

**Required:** alias `if:` must gate on the combined job result. A custom `if:`
that only checks `needs.guard.outputs.skip` **overrides** Actions' default
`success()` behavior — the stub will run and exit 0 even when `python-static`
failed, so required checks named `Ruff` / `Pyright` / … go green incorrectly.

```yaml
  ruff:
    name: Ruff
    needs: [guard, python-static]
    if: needs.guard.outputs.skip != 'true' && needs.python-static.result == 'success'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Covered by Python lint & format checks"
```

`github-repo-lint` fails both unsafe aliases (missing the result gate) and any
remaining split/alias jobs after cutover.

## Enforcement

`scripts/lib/repo-practices` (`rp_check_python_static_ci_job`, run by
`scripts/github-repo-lint`) fails the audit for Python repos that split these
checks, ship unsafe cutover aliases, omit the `Python lint & format checks` job,
or lack a canonical `.github/ci/python-static` wrapper. The scan covers **every**
workflow under `.github/workflows/` (not only `ci.yml`) so release-please matrix
no-ops and ungated `checks-action` publishers cannot false-green required
contexts. `--suggest` prints remediation lines.
