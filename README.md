# repository-helpers

[![CI](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml/badge.svg)](https://github.com/the-hcma/repository-helpers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Bash 5.x](https://img.shields.io/badge/bash-5.x-4EAA25?logo=gnu-bash&logoColor=white)

Pure Bash helpers for keeping repositories maintained: dependency update PRs,
repository practice audits, agent review automation, systemd user services, and
stacked PR workflow support (`gh-stack` or Graphite, selected per repo).

Headline tools: **`dep-updater`** (stacked dependency PRs), **`github-repo-lint`**
(org repo practices audit), **secret scanning** (gitleaks via
`scripts/dev/secret-scan` / CI), and **secret audit** (TruffleHog deep history via
`scripts/secret-audit` — see [docs/secret-audit-trufflehog.md](docs/secret-audit-trufflehog.md)).

## Command-line tools

Run scripts from a clone of this repo (paths below are relative to the repo root).
Most entry points accept `--help`.

| Tool | What it does |
| --- | --- |
| [`dep-updater`](#dep-updater) | Stacked dependency update PRs for one repo (or batch across clones) |
| [`dep-updater-batch-run`](#dep-updater-batch-run) | Daily `dep-updater --batch --all` + email report (systemd entry point) |
| [`github-repo-lint`](#github-repo-lint) | Audit / onboard org repos against practices (merge queue, workflows, …) |
| [`secret-scan`](#secret-scanning) | Local + CI gitleaks scan for leaked credentials (canonical org helper) |
| [`secret-audit`](#secret-audit-deep-scan) | TruffleHog deep scan (full git history); intake marker + periodic org sweep |
| [`setup-service` / systemd](#systemd--services) | Install and inspect optional daily user services |
| [`ship-and-review`](#wait-for-agent-review--ship-and-review) | Submit stack → wait for CI → agent review loop |
| [`start-development` / ship helpers](#development-workflow) | Worktrees, local CI gates, stack submit, CI wait |
| [`wait-for-agent-review`](#wait-for-agent-review--ship-and-review) | PR agent review loop (triage, quota fallback, operator email) |

### `dep-updater`

Creates **stacked dependency update PRs** for a single repository (or, with
`--batch --all`, org repos from the GitHub API that have a local clone under
configured scan roots). Supported ecosystems:
npm/pnpm, Python (`pip`, `uv`, `poetry`, `pipenv`), Rust/Cargo, and GitHub Actions.
Stacking follows the target repo’s `.github/stacking-tool` marker (`gh-stack` when
absent; explicit `graphite` keeps Graphite). npm, PyPI, and GitHub Actions releases
newer than **9 days** are skipped unless the bump fixes a CVE. Work runs in a
throwaway worktree under `--tmpdir` — the primary clone is not used for stack submit.

```bash
# Preview the plan (no git / worktree changes)
scripts/dep-updater --dry-run --dir /path/to/repo

# Apply updates for one repo (wait for CI + merge by default)
scripts/dep-updater --dir /path/to/repo

# One combined PR instead of one PR per package
scripts/dep-updater --batch --dir /path/to/repo

# CVE-fix bumps only
scripts/dep-updater --security-only --dir /path/to/repo

# Org membership via GitHub API; run clones under scan roots (skips archived;
# skips private unless --include-private; logs org repos with no local clone)
scripts/dep-updater --batch --all --no-wait-ci --no-wait-merge
```

Useful flags: `--ecosystem npm|python|rust|gha|auto`, `--report-json` (implies
`--dry-run --quiet`), `--merge-via gh|merge-queue`, `--cleanup`, `--rebase`.
See [Dependency Updates](#dependency-updates) for ecosystem policy details.

### `dep-updater-batch-run`

In service mode, this entry point runs `git fetch`, then `dep-updater --batch --all`,
and sends an SMTP report. `--print` writes the report to stdout instead; it skips
SMTP and the batch run. Configure `~/.config/dep-updater.env` from
`etc/dep-updater.env.example`.

```bash
# Report-only (no batch, no SMTP)
DEP_UPDATER_BATCH_SCAN_ROOT=/path/to/repos scripts/dep-updater-batch-run --print

# Full daily worker
systemctl --user start dep-updater.service
tail --follow=name --retry ~/scratch/repository-helpers/dep-updater-batch.log
```

### `github-repo-lint`

Audits GitHub repositories against org conventions: `protect-main` + classic
`main` protection, GitHub merge queue wiring, branch cleanup workflows,
release-age policy (Dependabot cooldown / pnpm `minimumReleaseAge`), license /
CODEOWNERS / cursor rules, stacking-tool marker, uv CVE workflow, and more.
`--suggest` prints remediation hints; `--apply-fix` repairs supported GitHub
settings and can queue candidate workflow PRs from the target clone.

```bash
# Current clone (when run inside a git repo with a GitHub origin)
scripts/github-repo-lint --suggest

# One repo by slug
scripts/github-repo-lint --repo OWNER/NAME --suggest

# New-repo onboarding checklist (strict expectations + SUGGEST hints)
scripts/github-repo-lint --new-repo --repo OWNER/NAME

# Every repo in the org
scripts/github-repo-lint --all --org the-hcma --suggest

# Repair supported settings (+ candidate workflow stack when run from the clone)
scripts/github-repo-lint --repo OWNER/NAME --apply-fix

# Daily compliance email over org repos from the GitHub API (systemd / cron entry)
scripts/github-repo-lint --enforcer
```

Requires an authenticated `gh` CLI and `jq`. Merge-queue-only subset:
`scripts/check-merge-settings` (same flags, `--merge-only` behavior). Full check
table: [github-repo-lint checks](#github-repo-lint-checks).

### Secret scanning

Org secret detection is **gitleaks**, wrapped by the canonical library
`scripts/lib/ci-secret-scan` (copied into consumer repos as `.github/ci/secret-scan`
and synced via `github-repo-lint`). CI runs it on every PR as a post-push triage
job; it is **not** currently a required merge-queue status check.

Run the same logic locally before you push (installs gitleaks under
`~/.cache/repository-helpers/bin` when needed):

```bash
# This repo (or pass another clone path as the first argument)
scripts/dev/secret-scan
scripts/dev/secret-scan /path/to/other-repo

# Consumer repos that adopted the CI wrapper
bash .github/ci/secret-scan
```

Optional env: `GITLEAKS_BASE` / `GITLEAKS_HEAD` for a PR-diff scan,
`GITLEAKS_VERSION` to override the pinned version, `CI_SECRET_SCAN_BIN_DIR` for
a non-sudo install path. On a leak, the helper prints `ERROR: SECRET_SCAN_LEAK`
with rotate / branch-quarantine guidance — do not push and hope CI catches it.

`pre-pr-checks` / `submit-stack` / `ship-and-review` run this scan as a planned
job when `.github/ci/secret-scan` or `scripts/dev/secret-scan` exists (escape
hatch: `PRE_PR_CHECKS_SKIP=secret-scan`). CI `secret-scan` still runs after push
for triage. Full-history / intake / periodic deep scans (TruffleHog) are
[#509](https://github.com/the-hcma/repository-helpers/issues/509) —
now implemented as `scripts/secret-audit` (see below).

### Secret audit (deep scan)

Full git history and org-wide sweeps use **TruffleHog** via `scripts/secret-audit`
(see [docs/secret-audit-trufflehog.md](docs/secret-audit-trufflehog.md)). After a
**clean** scan, `--write-marker` records intake in a **host-local ledger**
(`~/scratch/repository-helpers/secret-audit-intake.json` — not a git file;
disposable, regenerated by the nightly sweep). `github-repo-lint` reads that ledger
locally: a missing, stale, or corrupt entry FAILs `--new-repo` / `--strict-onboarding`
(#575); CI runs (no ledger on the runner) skip the check. The daily timer **does**
maintain the ledger.

```bash
scripts/secret-audit --repo OWNER/NAME
scripts/secret-audit --repo OWNER/NAME --write-marker
scripts/secret-audit --all --org the-hcma --include-private
```

Automation always passes `--no-update` to TruffleHog. Installs must match the
pinned release (`3.97.0`); a mismatched on-PATH binary is replaced from GitHub
releases after checksum verification.
On leaks: `ERROR: SECRET_AUDIT_LEAK` — rotate credentials; never record a clean intake.

Daily timer (optional): `scripts/setup-secret-audit` installs `secret-audit.service`
(05:00) running `scripts/secret-audit-batch-run` (org sweep + summary email; finding
details stay on the host under `secret-audit-runs/`). The sweep never writes markers,
so it leaves local clones clean. Org sweeps skip archived
repos; set `SECRET_AUDIT_REPORT_TO` in `~/.config/secret-audit.env` (see
`etc/secret-audit.env.example`) or reuse `DEP_UPDATER_REPORT_TO`.


### Development workflow

| Script | Purpose | Typical invocation |
| --- | --- | --- |
| `scripts/dev/approve-pending-deployments` | Approve WAITING GitHub environments (`github-repo-lint`, `dep-updater`) | `scripts/dev/approve-pending-deployments --pr <n>` |
| `scripts/dev/post-pr-submission-checks` | Poll required checks; print agent-friendly failure logs | `scripts/dev/post-pr-submission-checks --pr <n>` |
| `scripts/dev/pre-pr-checks` | Detect-first local CI (shellcheck, tests, Python/TS/Rust when present; secret-scan when adopted) | from `.worktrees/<stack>-wt`: `scripts/dev/pre-pr-checks` |
| `scripts/dev/start-development` | Prune/sync; create or resume a stack worktree | `scripts/dev/start-development --worktree my-change --no-interactive` |
| `scripts/dev/submit-stack` | `pre-pr-checks` → stack submit → CI wait | `scripts/dev/submit-stack` |

Never implement on the primary clone — always `cd` into the stack worktree first.
See [Development](#development).

### Other helpers

| Script | Purpose |
| --- | --- |
| `scripts/check-lockfile-drift` | Compare lockfiles to registry constraints (safe throwaway worktree) |
| `scripts/check-merge-settings` | Thin wrapper: merge + GitHub MQ checks only |
| `scripts/check-token-expiry` | Preflight a CI environment PAT's expiry; warn before CI starts failing |
| `scripts/grandfather-pnpm-release-age` | One-time pnpm `minimumReleaseAge` / exclude cutover for existing lockfiles |
| `scripts/on-deploy` | Example deploy hook; consumer repos implement their own |
| `scripts/trigger-agent-review` | Request a review from the configured agent profile |

Shared libraries live under `scripts/lib/` (`agent-review`, `ci-secret-scan`,
`on-deploy-deps`, `release-age-defaults`, `repo-practices`, `runner`, …).

### Systemd / services

| Script | Purpose |
| --- | --- |
| `scripts/setup-github-repo-lint` | Install `github-repo-lint` enforcer unit + timer |
| `scripts/setup-service` | Install worktree-aware `dep-updater` systemd user unit + timer |
| `scripts/show-services` | Read-only status of all service templates in this repo |

```bash
scripts/setup-service --status
scripts/setup-github-repo-lint --status
scripts/show-services
```

### Upcoming

Tracked work that extends the tools above (not shipped yet):

| Issue | What it will add |
| --- | --- |
| ~~[#509](https://github.com/the-hcma/repository-helpers/issues/509)~~ | **Shipped:** TruffleHog deep secret audit (`scripts/secret-audit`), host-local intake ledger ([#573](https://github.com/the-hcma/repository-helpers/issues/573)), lint check, systemd timer — see [docs/secret-audit-trufflehog.md](docs/secret-audit-trufflehog.md). |

### `wait-for-agent-review` / `ship-and-review`

After CI is green, `wait-for-agent-review` drives the PR review loop (CodeRabbit,
Copilot, Bugbot, humans): reply-before-resolve triage, quota fallback, early
complete when nothing is outstanding, and operator email. It does **not**
self-approve. Configure `~/.config/agent-review.env` from
`etc/agent-review.env.example`.

```bash
scripts/wait-for-agent-review loop --pr <n>
scripts/wait-for-agent-review check --pr <n>
scripts/wait-for-agent-review complete --pr <n>   # emails operator when complete_ready
```

`scripts/dev/ship-and-review` runs the full ship path: `pre-pr-checks` → stack
submit → CI wait (approves WAITING environments on the operator’s behalf) →
`wait-for-agent-review loop`.

```bash
scripts/dev/ship-and-review
scripts/dev/ship-and-review --no-submit --pr <n>   # PR already open
```

## Daily Services

This repo ships two optional systemd user services. They are separate on purpose:
dependency updates can create PRs, while repository-practices monitoring only reports
compliance drift and points to the explicit `--apply-fix` remediation command.

| Service | Script | Schedule | Purpose |
| --- | --- | --- | --- |
| `dep-updater.service` | `scripts/dep-updater-batch-run` | 03:00 daily | Create/update dependency PRs for org repos with local clones and email the run report. |
| `github-repo-lint.service` | `scripts/github-repo-lint` | 04:00 daily | Monitor org repos (GitHub API; default `the-hcma`) and email the repository-practices report. |

`dep-updater.service` is the automation worker. It fetches every local clone under
the scan root, runs `dep-updater --batch --all` (org API membership + local
checkouts), streams the run to
`~/scratch/repository-helpers/dep-updater-batch.log`, and sends a success, failure,
or timeout report by email. When updates are created, the report lists them from
structured JSON; when none are created, it says so explicitly. Org repos with no
local clone appear under **Skipped (no local clone)**.

`github-repo-lint.service` is the compliance monitor. It discovers repositories
from the GitHub org API (`orgs/<ORG>/repos`, default `the-hcma`; same source as
`github-repo-lint --org the-hcma --all`), runs strict repository-practices checks
for each one, emails the daily report, and exits non-zero when any repository
fails. It does not apply repairs automatically. Local scan-root clones are not
required for the audit (only for some `--apply-fix` workflow stacks).

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
Use `~/.config/github-repo-lint.env` when you need a different org
(`GITHUB_REPO_LINT_ORG`), include-private, or report settings.

`scripts/show-services` prints a read-only summary of every systemd service template
in this repo, including installed status, active/enabled state, timer next run,
configuration files, log tail commands, and setup command.

See [docs/SYSTEMD.md](docs/SYSTEMD.md) for service configuration, logs, timers, and
manual trial runs.

## Dependency Updates

Invocation and flags: [`dep-updater`](#dep-updater) /
[`dep-updater-batch-run`](#dep-updater-batch-run). Supported ecosystems and
policy defaults:

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
  Requires a Rust toolchain on the host (plus the `clippy` component for post-bump
  recovery):

  ```bash
  rustup component add clippy
  cargo install cargo-outdated --locked
  ```

  apt's Rust is too old for current `cargo-outdated` — install via rustup, and on
  Debian/Ubuntu add `build-essential pkg-config libssl-dev` for `openssl-sys` /
  `libgit2-sys`. Note that `~/.cargo/bin` is not on a systemd/cron `PATH` by
  default, so a timer-run batch can still report the tool missing after a
  successful interactive install. A host without it no longer fails the whole run:
  `--batch --all` skips those repos and lists them under **Skipped (missing
  tooling)** in the batch email, while a single-repo run still fails loudly.
- **GitHub Actions:** supports `.github/workflows/*.yml`, preserving existing `v`
  prefix style, updating major-only pins only on newer majors, and skipping SHA or
  local action pins.

For npm, PyPI, and GitHub Actions, registry releases newer than 9 days are skipped
unless the bump fixes a CVE.

See [dep-updater.plan.md](dep-updater.plan.md) for implementation details and
[dep-updater-hybrid-architecture.plan.md](dep-updater-hybrid-architecture.plan.md)
for the Bash + Python extraction proposal.

## Repository Practices

Invocation and flags: [`github-repo-lint`](#github-repo-lint). The audit covers
GitHub native merge queue wiring (org default), `protect-main`, classic branch
protection, branch cleanup workflows, release-age policy, license/CODEOWNERS
metadata, cursor rules, and uv Python CVE checks.

`--apply-fix` can repair supported GitHub settings such as Release Please squash
settings, the `protect-main` ruleset (squash-only + `merge_queue` SQUASH), and
classic `main` branch protection (GitHub MQ profile). When run from the target
repository clone, it also prepares candidate workflow fixes in a dedicated
`.worktrees/repo-practices-candidate-fixes-wt` worktree and submits them as a
stack for review (`gt track` / `gt submit` when the marker is `graphite`, or
`gh stack submit` when the marker is `gh-stack`). Candidate workflow templates live under
`scripts/lib/repo-practices-workflows/` so they can be reviewed and linted
directly. Disable org repos in Graphite’s merge-queue UI so Graphite does not
also try to land PRs (stacking via `gt` / `.github/stacking-tool` is separate).

### `github-repo-lint` checks

`scripts/lib/repo-practices` implements the audit. Use `--merge-only` (via
`scripts/check-merge-settings`) to run only the merge-queue subset.

| Check | Full audit | Merge-only | What it validates |
| --- | --- | --- | --- |
| Release Please squash settings | yes | yes | Repos with `release-please.yml` use squash-only merges on `main` |
| `protect-main` ruleset | yes | yes | Squash-only + GitHub `merge_queue` (`SQUASH`) on `refs/heads/main` when GitHub MQ, Release Please, or strict onboarding |
| Classic `main` protection | yes | — | CODEOWNERS reviews, CI contexts; no Graphite-only push restrictions (GitHub MQ profile) |
| GitHub merge queue wiring | yes | yes | `protect-main` `merge_queue`, `ci.yml` `merge_group`, dependabot auto-merge via `gh pr merge --auto` when `dependabot.yml` exists |
| Workflow file extensions | yes | — | `.github/workflows/*` use `.yml` (not `.yaml`) |
| Branch cleanup workflows | yes | — | `cleanup-branch-on-merge.yml`, `cleanup-merged-branches.yml`, canonical `merged-pr-closer.yml` |
| License / copyright / CODEOWNERS | yes | — | Top-level LICENSE with copyright notice; `.github/CODEOWNERS` with org owner |
| Agent review cursor rule | yes | — | `.cursor/rules/pr-ship-and-review.mdc` + `.cursor/skills/ship-and-review/SKILL.md` reference `wait-for-agent-review` and reply-before-resolve |
| Pre-PR checks cursor rule | yes* | — | `.cursor/rules/pre-pr-checks.mdc`: format before check + no truncated output; consumer repos resolve `scripts/dev/` via the repository-helpers clone (#579) (*missing, invalid, or bare-path FAILS `--new-repo` / `--strict-onboarding` (#575/#579); routine `--all` / `--suggest` emits SUGGEST and succeeds) |
| Git commit identity cursor rule | yes | — | `.cursor/rules/git-commit-identity.mdc` forbids agent/machine co-authors; agents must verify commit signing (`commit.gpgsign` / `user.signingkey`, pinentry-mac / passphrase / per-machine keys / clearsign probe) and `~/.cursor/cli-config.json` attribution, and surface setup instructions when either is missing |
| No secret exposure cursor rule | yes* | — | `.cursor/rules/no-secret-exposure.mdc`: never leak secrets into logs/transcripts/PRs/commits; allowlist or path-existence when inspecting config; rotate if leaked (*missing or invalid FAILS `--new-repo` / `--strict-onboarding` (#575); routine `--all` / enforcer SUGGEST-only) |
| Remote timeouts and retries cursor rule | yes* | — | `.cursor/rules/remote-timeouts-retries.mdc`: explicit timeouts on every remote call; bounded retries for transient failures only (`Retry-After` / cap / budget); anti-patterns for no-timeout calls and `while True` retries (*missing or invalid FAILS `--new-repo` / `--strict-onboarding`; routine `--all` / `--suggest` emits SUGGEST and succeeds) |
| Repo practices after config change | yes | — | `.cursor/rules/repo-practices-after-config-change.mdc` requires `github-repo-lint` after workflow/config edits; `pre-pr-checks` runs detect-first `repo-practices-lint` when the diff touches those paths |
| Session-start read guidance | yes | — | `.cursor/rules/read-agents-and-rules.mdc` requires reading `AGENTS.md` and `.cursor/rules/` at the start of every new agent session |
| Agent bootstrap (agent-agnostic) | yes* | — | `AGENTS.md` at root + a session-startup line telling the agent to load `.cursor/rules/*.mdc`; `CLAUDE.md` (an `@AGENTS.md` import, or a symlink to `AGENTS.md`) and `.github/copilot-instructions.md` shims so Claude Code / Copilot reach the same guidance (templates in `scripts/lib/repo-practices-agents/`) (*missing `AGENTS.md` / startup line / `CLAUDE.md` / copilot shim FAILS `--new-repo` / `--strict-onboarding` (#575/#579); routine `--all` / `--suggest` emits SUGGEST and succeeds) |
| Agent-bootstrap shims trackable | yes | — | `.gitignore` must not ignore `CLAUDE.md` or `.github/copilot-instructions.md` (mirrors the `.cursor/rules/` guard) (#575) |
| Secret-audit intake ledger | yes | — | Host-local `~/scratch/repository-helpers/secret-audit-intake.json` entry (`status=clean`, fresh) after a TruffleHog deep scan; missing / stale / corrupt FAILs `--new-repo` / `--strict-onboarding` (#575); not checked in CI ([docs/secret-audit-trufflehog.md](docs/secret-audit-trufflehog.md)) |
| Stacking-tool marker + rule | yes | — | `.github/stacking-tool` + thin stacking-tool cursor rule |
| Stacking docs consistency | yes | — | `gh-stack` marker vs leftover Graphite docs (`AGENTS.md` / pr-ship / `GRAPHITE.md`) |
| UV Python CVE check | yes | — | `uv.lock` + `pyproject.toml` repos require canonical `.github/workflows/cve-check.yml` |
| UV + Release Please lock sync | yes | — | uv + `release-please.yml` repos require `release-please-config` `extra-files` bumping `uv.lock` via `@.name.value` jsonpath ([release-please#2561](https://github.com/googleapis/release-please/issues/2561)) |
| Python static CI job | yes | — | Python (`pyproject.toml` + ruff) repos run ruff check/format + typecheck in one `Python lint & format checks` job via `.github/ci/python-static`; no split `Ruff`/`Pyright`/`Mypy`/`Backend Lint` publishers in **any** workflow; cutover must share the combined job/step conclusion |
| `.cursor/rules` gitignore | yes | — | `.gitignore` must not block `.cursor/rules/` |
| Dependabot release age | yes | — | `cooldown` on every `dependabot.yml` updates entry (`release-age-defaults`) |
| pnpm release age | yes | — | `minimumReleaseAge` in `pnpm-workspace.yaml` when present |
| pnpm Corepack CI | yes | — | Exact `packageManager: pnpm@X.Y.Z` when lockfile exists; no `pnpm/action-setup` / `setup-node` `cache: pnpm`; use org composite [`actions/setup-pnpm-corepack`](actions/setup-pnpm-corepack/README.md) (pin SHA on `main`) |
| `ci-secret-scan` gitleaks pin | yes* | — | Warn when `scripts/lib/ci-secret-scan` pins gitleaks behind the release-age-eligible version (*this repo only) |
| GitHub-native security settings | yes* | — | Dependabot alerts, Dependabot security updates, secret scanning + push protection (free on public repos, GHAS-gated on private — advisory only there), private vulnerability reporting; `--apply-fix` toggles each via the GitHub API (*enforceable (public-repo-available) settings FAIL under `--new-repo` and `--strict-onboarding`; private-repo advisory-only settings (secret scanning, private vulnerability reporting when GHAS-gated) always SUGGEST, never FAIL; routine `--all` / `--suggest` SUGGESTs throughout — org-wide rollout complete, repository-helpers#588) |
| Actions hardening | yes* | — | `default_workflow_permissions: read` and `can_approve_pull_request_reviews: false` (`--apply-fix` sets both); `allowed_actions` and `sha_pinning_required` are SUGGEST-only always (no safe default to auto-apply) (*`default_workflow_permissions` / `can_approve_pull_request_reviews` FAIL under `--new-repo` and `--strict-onboarding`; SUGGEST in routine `--all` / `--suggest` — org-wide rollout complete, repository-helpers#588) |
| Actions workflow `uses:` pinning | yes* | — | Third-party `uses:` refs pinned to a full commit SHA; a release/publish workflow (holds OIDC / write tokens) with a non-SHA pin is promoted past a generic suggestion (*generic non-SHA pins are SUGGEST always; release/publish workflow pins FAIL under `--new-repo` and `--strict-onboarding` — org-wide rollout complete, repository-helpers#588) |
| Deployment environment protection | yes* | — | Any environment a workflow deploys to must have a protection rule (required reviewer) or a `deployment_branch_policy` (*missing FAILS `--new-repo` and `--strict-onboarding`; SUGGESTs in routine `--all` / `--suggest` — org-wide rollout complete, repository-helpers#588) |
| Protection-mechanism consistency | yes | — | Advisory only: flags a genuine disagreement between classic `main` protection and the `protect-main` ruleset (e.g. `require_code_owner_reviews`) — this org runs both by design, so their coexistence is never itself flagged (repository-helpers#588) |

`--suggest` prints remediation lines; `--apply-fix` queues candidate
workflow/cursor-rule PRs via the stacking backend selected by
`.github/stacking-tool` (`graphite` → `gt track` / `gt submit`; `gh-stack` →
`gh stack init` / `gh stack submit`).

Further detail (protect-main rules, branch hygiene, CVE workflow template):
[AGENTS.md](AGENTS.md#repository-practices-new-and-existing-repos).

## Systemd Service Setup

`scripts/setup-service` reads unit templates from `etc/systemd/<unit>.service`
in the invoking repository, substitutes `@@REPO_DIR@@`, injects `DEPLOYED_COMMIT`
and `ConditionHost=|<machine-id>` guards, installs under `~/.config/systemd/user/`, and keeps a
readable copy under `~/.config/share/systemd-units/` for `scripts/show-services`. Enables companion timers when
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
scripts/dev/pre-pr-checks          # detect-first local CI mirror (includes secret-scan when adopted)
scripts/dev/secret-scan            # optional: same gitleaks path without full pre-pr
scripts/dev/submit-stack           # pre-pr-checks + stack submit + CI wait
```

`pre-pr-checks` plans a **secret-scan** job when `.github/ci/secret-scan` or
`scripts/dev/secret-scan` exists. That is the submit-path gate; CI
`secret-scan` still runs after push for triage. Skip only with
`PRE_PR_CHECKS_SKIP=secret-scan`. Org-wide / historical deep scans are tracked
separately (repository-helpers#509).

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

**Merging (org default):** use GitHub’s merge queue (`gh pr merge --auto --squash` /
Enable auto-merge). Do **not** use the `merge-it` label to land PRs — leftover
labels are ignored. Graphite stacking (`gt`) remains available via
`.github/stacking-tool`; disable Graphite’s merge-queue UI for org repos.

Configure `~/.config/agent-review.env` from `etc/agent-review.env.example` (SMTP,
`AGENT_REVIEW_REPORT_TO`, early-complete when nothing outstanding, **12h** PR
non-convergence cap).

See [AGENTS.md](AGENTS.md) for coding conventions, utility index, and agent-review
details; [`.cursor/rules/stacking-tool.mdc`](.cursor/rules/stacking-tool.mdc) for
backend selection; [`.cursor/skills/ship-and-review/SKILL.md`](.cursor/skills/ship-and-review/SKILL.md)
for the full review playbook; skills under `.cursor/skills/{graphite,gh-stack}/`.

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
