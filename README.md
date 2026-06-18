# repository-helpers

[![CI](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml/badge.svg)](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Bash 5.x](https://img.shields.io/badge/bash-5.x-4EAA25?logo=gnu-bash&logoColor=white)

Pure Bash helpers for keeping repositories maintained: dependency update PRs, repository
practice audits, systemd user services, and Graphite-based development workflow support.

## Highlights

- `scripts/dep-updater` creates stacked dependency update PRs for npm/pnpm, Python
  (`pip`, `uv`, `poetry`, `pipenv`), Rust/Cargo, and GitHub Actions.
- `scripts/dep-updater-batch-run` runs dependency updates across every clone under a
  scan root, streams a live log, and sends a daily email report.
- `scripts/github-repo-lint` audits org repository settings such as Graphite merge
  queue wiring, `protect-main`, classic branch protection, branch cleanup workflows,
  and Dependabot auto-merge.
- `scripts/github-repo-lint --enforcer` runs those practice checks daily across local
  clones and emails a compliance report.
- `scripts/setup-service` installs worktree-aware systemd user services from templates.
- `scripts/dev/start-development` creates and resumes Graphite worktrees safely.

## Daily Services

This repo ships two optional systemd user services. They are separate on purpose:
dependency updates can create PRs, while repository-practices monitoring only reports
compliance drift and points to the explicit `--apply-fix` remediation command.

| Service | Script | Schedule | Purpose |
| --- | --- | --- | --- |
| `dep-updater.service` | `scripts/dep-updater-batch-run` | 03:00 daily | Create/update dependency PRs across a scan root and email the run report. |
| `github-repo-lint.service` | `scripts/github-repo-lint` | 04:00 daily | Monitor local GitHub clones for repository-practices compliance and email the report. |

`dep-updater.service` is the automation worker. It fetches every repository under
the scan root, runs `dep-updater --batch --all`, streams the run to
`~/scratch/repository-helpers/dep-updater-batch.log`, and sends a success, failure,
or timeout report by email. When updates are created, the report lists them from
structured JSON; when none are created, it says so explicitly.

`github-repo-lint.service` is the compliance monitor. It discovers local
GitHub clones under a scan root, runs strict repository-practices checks for each
one, emails the daily report, and exits non-zero when any repository fails. It does
not apply repairs automatically.

Install or inspect them from this repository:

```bash
cp etc/dep-updater.env.example ~/.config/dep-updater.env
chmod 600 ~/.config/dep-updater.env

scripts/setup-service
scripts/setup-service --status

scripts/setup-github-repo-lint
scripts/setup-github-repo-lint --status

scripts/show-services
```

`github-repo-lint` (no args) reuses `~/.config/dep-updater.env` for SMTP by default.
Use `~/.config/github-repo-lint.env` when you need a different scan root or
report settings.

`scripts/show-services` prints a read-only summary of every systemd service template
in this repo, including installed status, active/enabled state, timer next run,
configuration files, log tail commands, and setup command.

See [docs/SYSTEMD.md](docs/SYSTEMD.md) for service configuration, logs, timers, and
manual trial runs.

## Dependency Updates

Run against one repository:

```bash
scripts/dep-updater --dry-run --dir /path/to/repo
scripts/dep-updater --dir /path/to/repo
```

Run across all repositories under a scan root through the service wrapper:

```bash
DEP_UPDATER_BATCH_SCAN_ROOT=/path/to/repos scripts/dep-updater-batch-run --print
systemctl --user start dep-updater.service
tail --follow=name --retry ~/scratch/repository-helpers/dep-updater-batch.log
```

Supported ecosystems and policy defaults:

- **npm / pnpm:** reads `package.json`, lockfiles, and workspace config. Exact pins
  are updated in place; workspace, local, file, link, and git refs are skipped.
- **Python / pip:** supports `requirements.txt` and `pyproject.toml`, writes `>=`
  floor constraints, and respects intentional `==` pins.
- **Python / uv:** supports `uv.lock`; `==` pins are updated and promoted to `>=`,
  with dry-run install checks guarding transitive constraints.
- **Python / Poetry:** supports `poetry.lock`, respecting intentional `==` pins.
- **Python / Pipenv:** supports `Pipfile.lock`, respecting intentional `==` pins.
- **Rust / Cargo:** supports `Cargo.toml` / `Cargo.lock` using `cargo outdated`
  JSON and `cargo add`, preserving dev/build kind and workspace package targeting.
- **GitHub Actions:** supports `.github/workflows/*.yml`, preserving existing `v`
  prefix style, updating major-only pins only on newer majors, and skipping SHA or
  local action pins.

For npm packages, registry releases newer than 9 days are skipped unless the bump
fixes a CVE.

See [dep-updater.plan.md](dep-updater.plan.md) for implementation details and
[dep-updater-hybrid-architecture.plan.md](dep-updater-hybrid-architecture.plan.md)
for the Bash + Python extraction proposal.

## Repository Practices

`scripts/github-repo-lint` audits org conventions including Graphite merge
queue wiring, branch protection, cleanup workflows, Dependabot auto-merge,
Release Please settings, top-level license/copyright metadata, and CODEOWNERS
coverage for all files.

Audit one repository:

```bash
scripts/github-repo-lint --repo OWNER/NAME --suggest
```

Audit a new repository with strict onboarding expectations:

```bash
scripts/github-repo-lint --new-repo --repo OWNER/NAME
```

Apply supported GitHub-side fixes:

```bash
scripts/github-repo-lint --repo OWNER/NAME --apply-fix
```

`--apply-fix` can repair supported GitHub settings such as Release Please squash settings,
the `protect-main` ruleset, and classic `main` branch protection. When run from the
target repository clone, it also prepares candidate workflow fixes in a dedicated
`.worktrees/repo-practices-candidate-fixes-wt` worktree and submits them as a
Graphite stack for review. Candidate workflow templates live under
`scripts/lib/repo-practices-workflows/` so they can be reviewed and linted directly.
Graphite app merge queue configuration remains a manual step and is reported as such.

## Systemd Service Setup

`scripts/setup-service` installs user units from
`share/systemd-unit-templates/<unit>.service` (or a gitignored per-repo
`etc/systemd/` override), substitutes `@@REPO_DIR@@`, injects `DEPLOYED_COMMIT`
and `ConditionHost=`, and enables the companion timer when
`share/systemd-unit-templates/<unit>.timer` exists.

For service repositories, provide an executable `scripts/on-deploy` hook:

| Exit code | Meaning |
| --- | --- |
| `0` | Build or sync steps ran; the service must restart. |
| `1` | Nothing changed; restart may be skipped. |
| `2+` | Failure; setup aborts. |

Use `scripts/lib/on-deploy-deps` from this repo for Python and pnpm dependency
staleness checks. See [AGENTS.md](AGENTS.md#on-deploy-hooks) and
[docs/on-deploy-deps-load.snippet](docs/on-deploy-deps-load.snippet).

## Development

Start work in a Graphite worktree:

```bash
scripts/dev/start-development --worktree my-change --no-interactive
```

Before submitting a stack:

```bash
scripts/dev/pre-pr-checks
scripts/dev/submit-stack
```

See [AGENTS.md](AGENTS.md) for coding conventions and [GRAPHITE.md](GRAPHITE.md) for
the branch stacking and PR workflow.

## Testing

Run the full local CI mirror:

```bash
scripts/dev/pre-pr-checks
```

Focused tests live in `tests/` and can be run directly:

```bash
bash tests/dep-updater.test
bash tests/dep-updater-batch-run.test
bash tests/aa-github-repo-lint.test
bash tests/a-github-repo-lint-enforcer.test
bash tests/setup-service.test
```

## License

MIT. Copyright (c) 2026 Henrique Andrade / thehcma. See [LICENSE](LICENSE).
