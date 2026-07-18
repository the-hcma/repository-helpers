# repository-helpers

[![CI](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml/badge.svg)](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Bash 5.x](https://img.shields.io/badge/bash-5.x-4EAA25?logo=gnu-bash&logoColor=white)

Pure Bash helpers for keeping repositories maintained: dependency update PRs,
repository practice audits, agent review automation, systemd user services, and
stacked PR workflow support (`gh-stack` or Graphite, selected per repo).

## Highlights

- `scripts/dep-updater` creates stacked dependency update PRs for npm/pnpm, Python
  (`pip`, `uv`, `poetry`, `pipenv`), Rust/Cargo, and GitHub Actions.
- `scripts/dep-updater-batch-run` runs dependency updates across every clone under a
  scan root, streams a live log, and sends a daily email report.
- `scripts/github-repo-lint` audits org repository settings (merge queue, branch
  protection, workflows, release-age policy, metadata, and more — see
  [github-repo-lint checks](#github-repo-lint-checks)).
- `scripts/github-repo-lint --enforcer` runs those practice checks daily across local
  clones and emails a compliance report.
- `scripts/wait-for-agent-review` runs the PR agent review loop (CodeRabbit, Copilot,
  Bugbot, humans): CI gating, reply-before-resolve triage, early-complete when
  nothing is outstanding, quota fallback, and operator email (no self-approve).
- `scripts/dev/ship-and-review` submits the stack (`gh stack` or `gt`), waits for CI,
  then runs the agent review loop end-to-end.
- `scripts/setup-service` installs worktree-aware systemd user services from templates.
- `scripts/dev/start-development` creates and resumes stack worktrees safely
  (marker-aware sync via `.github/stacking-tool`).

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

`scripts/github-repo-lint` audits org conventions: merge queue wiring (Graphite MQ
or GitHub’s native merge queue), `protect-main`, classic branch protection, branch
cleanup workflows, release-age policy, license/CODEOWNERS metadata, cursor rules,
and uv Python CVE checks. See [github-repo-lint checks](#github-repo-lint-checks)
for the full list.

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

`--apply-fix` can repair supported GitHub settings such as Release Please squash
settings, the `protect-main` ruleset, and classic `main` branch protection. When
run from the target repository clone, it also prepares candidate workflow fixes in
a dedicated `.worktrees/repo-practices-candidate-fixes-wt` worktree and submits
them as a stacked PR for review. Candidate workflow templates live under
`scripts/lib/repo-practices-workflows/` so they can be reviewed and linted
directly. Graphite app merge queue configuration (for Graphite MQ repos) remains a
manual step and is reported as such.

### `github-repo-lint` checks

`scripts/lib/repo-practices` implements the audit. Use `--merge-only` (via
`scripts/check-merge-settings`) to run only the merge-queue subset.

| Check | Full audit | Merge-only | What it validates |
| --- | --- | --- | --- |
| Release Please squash settings | yes | yes | Repos with `release-please.yml` use squash-only merges on `main` |
| `protect-main` ruleset | yes | yes | Squash-only + Graphite App bypass **or** GitHub `merge_queue` on `refs/heads/main` when `merge-it`, GitHub MQ, or Release Please |
| Classic `main` protection | yes | — | CODEOWNERS reviews, CI contexts; Graphite-only push on Graphite MQ repos (org standard) |
| Graphite / GitHub merge queue | yes | yes | Graphite: `merge-it` (strict), `merge-mq` when present, `merged-pr-closer.yml`, `ci.yml` `gtmq_merge_*` skip, dependabot auto-merge when `dependabot.yml` exists. GitHub MQ: `ci.yml` `merge_group` |
| Workflow file extensions | yes | — | `.github/workflows/*` use `.yml` (not `.yaml`) |
| Branch cleanup workflows | yes | — | `cleanup-branch-on-merge.yml`, `cleanup-merged-branches.yml`, canonical `merged-pr-closer.yml` |
| License / copyright / CODEOWNERS | yes | — | Top-level LICENSE with copyright notice; `.github/CODEOWNERS` with org owner |
| Agent review cursor rule | yes | — | `.cursor/rules/pr-ship-and-review.mdc` + `.cursor/skills/ship-and-review/SKILL.md` reference `wait-for-agent-review` and reply-before-resolve |
| UV Python CVE check | yes | — | `uv.lock` + `pyproject.toml` repos require canonical `.github/workflows/cve-check.yml` |
| Python static CI job | yes | — | Python (`pyproject.toml` + ruff) repos run ruff check/format + typecheck in one `Python lint & format checks` job via `.github/ci/python-static`; no split `Ruff`/`Pyright`/`Mypy`/`Backend Lint` publishers in **any** workflow; cutover must share the combined job/step conclusion |
| `.cursor/rules` gitignore | yes | — | `.gitignore` must not block `.cursor/rules/` |
| Dependabot release age | yes | — | `cooldown` on every `dependabot.yml` updates entry (`release-age-defaults`) |
| pnpm release age | yes | — | `minimumReleaseAge` in `pnpm-workspace.yaml` when present |
| pnpm Corepack CI | yes | — | Exact `packageManager: pnpm@X.Y.Z` when lockfile exists; no `pnpm/action-setup` / `setup-node` `cache: pnpm`; use org composite [`actions/setup-pnpm-corepack`](actions/setup-pnpm-corepack/README.md) (pin SHA on `main`) |
| `ci-secret-scan` gitleaks pin | yes* | — | Warn when `scripts/lib/ci-secret-scan` pins gitleaks behind the release-age-eligible version (*this repo only) |

`--suggest` prints remediation lines; `--apply-fix` queues candidate
workflow/cursor-rule PRs via the repo’s stacking tool in the target clone.

Further detail (protect-main rules, branch hygiene, CVE workflow template):
[AGENTS.md](AGENTS.md#repository-practices-new-and-existing-repos).

## Systemd Service Setup

`scripts/setup-service` reads unit templates from `etc/systemd/<unit>.service`
in the invoking repository, substitutes `@@REPO_DIR@@`, injects `DEPLOYED_COMMIT`
and `ConditionHost=|<machine-id>` guards, installs under `~/.config/systemd/user/`, and mirrors expanded
units to `~/.config/share/systemd-units/`. Enables companion timers when
`etc/systemd/<unit>.timer` exists.

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

Stacking backend is selected by `.github/stacking-tool` (`gh-stack` or `graphite`).
**This repo trials `gh-stack`.** Never edit the primary clone directly — work in a
stack worktree.

```bash
scripts/dev/start-development --worktree my-change --no-interactive
cd .worktrees/my-change-wt

# gh-stack (this repo):
gh stack init my-change/topic
# … commit …
# gh stack add my-change/next-layer   # optional extra layer

# graphite (when .github/stacking-tool is graphite):
# gt create my-change/topic -m 'feat: …'
```

Local quality gates and submit (prefer these over bare `gh stack submit` / `gt submit`):

```bash
scripts/dev/pre-pr-checks          # bash -n, shellcheck, all tests/*.test
scripts/dev/submit-stack           # pre-pr-checks + stack submit + CI wait
```

End-to-end ship (submit + CI + agent review loop):

```bash
scripts/dev/ship-and-review
# or, when the PR already exists:
scripts/dev/ship-and-review --no-submit --pr <n>
```

After every push, wait for CI on the PR head (included in `submit-stack` by default):

```bash
scripts/dev/post-pr-submission-checks --pr <n>
```

When CI is green, run the agent review loop. **Reply on-thread before resolving**
(exit code 3 means feedback still needs a human reply):

```bash
scripts/wait-for-agent-review loop --pr <n>
```

When `check` reports `complete_ready: true` (agent sign-off on the current head):

```bash
scripts/wait-for-agent-review complete --pr <n>   # emails the operator; does not self-approve
```

**Merging this repo:** use GitHub’s merge queue (`gh pr merge --auto --squash` /
Enable auto-merge). Do **not** use the `merge-it` label here — that enqueues
Graphite MQ on other org repos.

Configure `~/.config/agent-review.env` from `etc/agent-review.env.example` (SMTP,
`AGENT_REVIEW_REPORT_TO`, early-complete when nothing outstanding, **12h** PR
non-convergence cap).

See [AGENTS.md](AGENTS.md) for coding conventions, utility index, and agent-review
details; [`.cursor/rules/stacking-tool.mdc`](.cursor/rules/stacking-tool.mdc) for
backend selection; [`.cursor/skills/ship-and-review/SKILL.md`](.cursor/skills/ship-and-review/SKILL.md)
for the full review playbook; skills under `.cursor/skills/{graphite,gh-stack}/`.

## Scripts reference

| Script | Purpose |
| --- | --- |
| `scripts/dep-updater` | Dependency bumps → stacked PR(s) for one repo. |
| `scripts/dep-updater-batch-run` | Daily batch across a scan root; email report. |
| `scripts/github-repo-lint` | Org repo practices audit / `--apply-fix`. |
| `scripts/check-merge-settings` | Merge + Graphite MQ settings only. |
| `scripts/check-lockfile-drift` | Lockfile vs manifest drift check. |
| `scripts/grandfather-pnpm-release-age` | One-time pnpm release-age cutover helper. |
| `scripts/wait-for-agent-review` | Agent review loop, triage, operator email (no self-approve). |
| `scripts/trigger-agent-review` | Request a review from the configured agent profile. |
| `scripts/setup-service` | Install worktree-aware systemd user unit. |
| `scripts/setup-github-repo-lint` | Install repo-lint timer/service. |
| `scripts/show-services` | Status of all service templates in this repo. |
| `scripts/dev/start-development` | Worktree + marker-aware stack sync. |
| `scripts/dev/pre-pr-checks` | Full local CI mirror. |
| `scripts/dev/submit-stack` | Checks, submit, CI wait. |
| `scripts/dev/post-pr-submission-checks` | PR CI poll + agent-friendly failure logs. |
| `scripts/dev/ship-and-review` | Submit + CI + agent review loop. |

Shared libraries: `scripts/lib/` (`runner`, `repo-practices`, `agent-review`,
`on-deploy-deps`, `release-age-defaults`, …).

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
