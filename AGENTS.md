# AGENTS.md — Ground Rules for repository-helpers

This file defines the non-negotiable standards for all contributors (human or AI) working on this codebase. Every change must comply with these rules before it is considered complete.

---

## Utilities overview

Top-level scripts (see [README.md](./README.md) for operator-oriented summaries):

| Area | Script | Role |
| --- | --- | --- |
| Dependencies | `scripts/dep-updater` | Create stacked dependency-update PRs (npm, Python, Rust, Actions). |
| Batch automation | `scripts/dep-updater-batch-run` | Daily `--batch --all` across a scan root; email report. |
| Repo practices | `scripts/github-repo-lint` | Audit/onboard org repos (merge queue, `protect-main`, workflows). |
| Merge settings | `scripts/check-merge-settings` | Thin wrapper (merge + Graphite only). |
| Lockfile drift | `scripts/check-lockfile-drift` | Compare lockfiles to registry constraints. |
| pnpm cutover | `scripts/grandfather-pnpm-release-age` | One-time `minimumReleaseAgeExclude` for existing lockfiles. |
| Systemd | `scripts/setup-service`, `scripts/setup-github-repo-lint`, `scripts/show-services` | Install timers/units; status summary. |
| Deploy hook | `scripts/on-deploy` | Example hook; consumer repos implement their own. |
| Agent review | `scripts/wait-for-agent-review`, `scripts/trigger-agent-review` | PR review loop, triage, operator email (no self-approve). |
| Dev workflow | `scripts/dev/start-development` | Worktree + Graphite sync entry point. |
| Dev workflow | `scripts/dev/pre-pr-checks` | Local CI mirror (`bash -n`, `shellcheck`, all tests). |
| Dev workflow | `scripts/dev/submit-stack` | `pre-pr-checks` → `gt submit` → `post-pr-submission-checks`. |
| Dev workflow | `scripts/dev/post-pr-submission-checks` | Wait for PR CI; print agent-friendly failure excerpts. |
| Dev workflow | `scripts/dev/ship-and-review` | Submit + CI wait + `wait-for-agent-review loop`. |

Shared libraries live under `scripts/lib/` (runner, repo-practices, agent-review, on-deploy-deps, release-age-defaults, …).

---

## Language & Runtime

- Scripts live in `scripts/` (e.g. `scripts/dep-updater`, `scripts/setup-service`). Sub-directories are allowed (e.g. `scripts/dev/start-development`).
- Tests live in `tests/` and mirror the script name (e.g. `tests/dep-updater.test`).
- Target **bash ≥ 5.x** (every script declares `#!/usr/bin/env bash` and uses `set -euo pipefail`).
- External runtime dependencies: `git`, `gt` (Graphite CLI), `gh` (GitHub CLI), `jq`,
  `rg` (ripgrep), `actionlint`, plus the ecosystem tools being managed (`pnpm`,
  `pip`, `uv`, `poetry`) as optional callees.
- No Node.js helpers, no Python scripting. Keep the implementation pure Bash.
- Test harnesses are plain Bash — no test framework installs required.

---

## Formatting & Style

- **No automated formatter.** Consistency is enforced by the conventions below and by `shellcheck`.
- Indentation: **2 spaces**. Never tabs.
- Line length: soft limit of **100 characters**; hard limit of **120**. Comments may exceed only when a long URL would otherwise be broken.
- Function definitions use the `name() {` form (no `function` keyword).
- Opening `{` stays on the same line as the function name or control keyword.
- Always quote variable expansions: `"$var"`, `"${array[@]}"`.
- Prefer `[[` over `[` for conditionals.
- Use `$(...)` for command substitution, never backticks.

---

## Linting

- **`shellcheck`** is mandatory. CI runs `shellcheck -S info dep-updater dep-updater.test` on every push.
- Zero findings at the `info` level is the bar. No `# shellcheck disable=` suppressions unless absolutely unavoidable; every suppression must have a comment explaining why.
- Key rules that are always errors:
  - **SC2155** — never combine `local`/`readonly` with a command substitution assignment; declare separately to preserve the exit code.
  - **SC2015** — never use `A && B || C` as a substitute for `if/then/else`; C will run whenever B fails.
  - **SC2086** — always double-quote expansions unless word-splitting is explicitly intended.

---

## Testing

- Test files live in `tests/` with no extension (e.g. `tests/dep-updater.test`).
- Run with: `bash tests/<script-name>.test`
- Tests are grouped into sections (`=== section name ===`). Each test prints `[PASS]` or `[FAIL]` and the suite exits non-zero if anything fails.
- **Every new behaviour or bug fix must be accompanied by a test**, even if that test is a dry-run smoke test or a static-analysis assertion (`awk`/`grep` over the source).
- Tests must be **deterministic**: no `sleep` for timing, no real network calls, no real git operations on remote state.
- Static analysis tests (e.g. "no `local -r` inside loops") live in a dedicated `=== static: ... ===` section.
- Shared libs must not hardcode sibling org repo names; discover via `rp_DEFAULT_ORG` (`the-hcma`) helpers (`rp_discover_org_repos`, etc.). Enforce with `rp_assert_no_hardcoded_consumer_repo_names` in `tests/lib/test-assert` (see `.cursor/rules/no-hardcoded-org-repos.mdc`).
- Test names must read as sentences: `output contains "[worktree] Creating worktree at:"`.
- Do not write tests that only assert a function was reached — assert the observable output or exit code.

---

## Repository

- Remote: `https://github.com/the-hcma/repository-helpers` (private).
- Do not make the repository public without explicit approval.
- Never commit secrets, credentials, or API keys — use environment variables.

---

## dep-updater Behavioral Invariants

- **Never introduce `==` pins (Python).** dep-updater always writes `>=` floor constraints when bumping a Python dependency. It must never lock a package to an exact version.
- **Respect existing pins for pip / pipenv / poetry.** For these ecosystems, `==` signals a deliberate user decision to lock a specific version. dep-updater skips those packages entirely (`py_is_pinned`).
- **uv `==` pins are not treated as intentional freezes.** dep-updater updates them and promotes the constraint to `>=` on bump. The transitive constraint check (`uv pip install --dry-run`) still gates upgrades that would violate real transitive constraints.
- **npm exact pins are updated in place, not skipped.** An exact version in `package.json` (e.g. `"vitest": "4.1.4"`) is bumped to the new version while preserving the exact style (no promotion to `^`). This matches Dependabot's behaviour. Local/git references (`workspace:`, `file:`, `link:`, `git`) are still skipped.
- **Release age (dep-updater 9 days, Dependabot 10 days).** dep-updater does not propose bumps to registry versions published less than **9 days** ago (`scripts/lib/release-age-defaults`). Dependabot `cooldown` on managed repos is **one day longer** (10 days) so dep-updater lands updates first. When the target project sets a higher `minimumReleaseAge` in `pnpm-workspace.yaml`, the larger value is used for npm. The same 9-day gate applies to Python/PyPI and GitHub Actions bumps.
- **npm picks the newest eligible version, not only dist-tags.latest.** When `dist-tags.latest` is still inside the release-age window, dep-updater walks stable registry versions (newest-first) and proposes the newest one that passes release-age and closure checks — matching Dependabot cooldown behaviour and GitHub Actions `_gha_pick_eligible_new_ref`.
- **TypeScript major bumps are held.** dep-updater does not propose `typescript` major upgrades (e.g. 6.x → 7.x). TypeScript 7 removed the programmatic APIs that `typescript-eslint` needs, so majors break ESLint CI until upstream supports them. Same-major patch/minor bumps still land; CVE-driven majors are still allowed.
- **CVE / security bumps can land early.** Dependabot **security** PRs ignore the version-update `cooldown` and may open immediately. **dep-updater** skips the 9-day gate when `npm audit` or `pip-audit` reports a CVE fix (`npm_pkg_has_cve_fix_in_audit` / `py_pkg_has_cve_fix_in_audit`). Routine **version-update** PRs from Dependabot still wait 10 days (weekly scan + cooldown); dep-updater usually lands those first — close redundant Dependabot version PRs when appropriate.
- **pnpm grandfathering (cutover only).** When enabling `minimumReleaseAge` on a repo with an existing lockfile, run `scripts/grandfather-pnpm-release-age` once to write `pnpm-workspace.yaml` with `minimumReleaseAgeExclude: ["*"]` so the current lockfile keeps passing CI under pnpm 11.1.3+. No registry file or prune step—**forward** bumps are gated by dep-updater (9 days) and Dependabot cooldown (10 days).
- **GitHub Actions pins follow their own style.** `@v6` (major-only) bumps to the latest release semver when newer—patch within the same major (`v6` → `v6.0.2`) or major jump (`v7` → `v8.1.0`), matching Dependabot. `@v1.7.12` / `@0.36.0` (full semver) is bumped on any newer release. The `v`-prefix style of the existing pin is preserved. Commit-SHA pins (`@abc1234...`) and local actions (`./path`) are never touched.
- **Wait timeouts must be machine-parseable.** Any long-running wait loop (CI gating, merge polling, PR number discovery, etc.) must, on timeout, emit **one** concise line starting with `ERROR: WAIT_TIMEOUT ...` and then fail. Avoid multi-line timeout chatter — batch runs (`--batch --all`) postprocess these lines into end-of-run actionable summaries.
- **GNU userland on macOS.** Prefer Homebrew gnubin on `PATH` via
  `tooling_path_ensure_gnu_userland` / the cron and node bootstraps
  (`brew install coreutils gnu-sed grep util-linux`) so scripts can assume GNU
  `sed`, `grep -P`, `date -Is`, `timeout`, and `flock`. On Darwin, missing or BSD
  tools fail early with an install hint — do not rely on silent fallback.
  Do not add BSD vs GNU branches at call sites. `dep-updater` in-place
  edits still resolve GNU sed explicitly (`gsed` /
  `tooling_prereq_gnu_sed_path`) as an additional hard prerequisite.

---

## Repository practices (new and existing repos)

Run **`scripts/github-repo-lint`** to audit or onboard a GitHub repository against org conventions (merge settings, Graphite merge queue, branch cleanup, Dependabot auto-merge, and dependency release-age policy: Dependabot `cooldown` and pnpm `minimumReleaseAge` per `scripts/lib/release-age-defaults`).

```bash
scripts/github-repo-lint --new-repo --repo OWNER/NAME       # checklist + SUGGEST hints
scripts/github-repo-lint --repo OWNER/NAME --suggest        # audit one repo with remediation lines
scripts/github-repo-lint --all --org the-hcma               # every repo in the org
scripts/github-repo-lint --apply-fix --repo OWNER/NAME      # patch settings + candidate workflow PRs
```

**`scripts/check-merge-settings`** is a thin wrapper (merge + Graphite only). Prefer **`github-repo-lint`** for full coverage including branch cleanup workflows.

### `github-repo-lint` checks

Operator-oriented copy of this table also lives in [README.md](README.md#github-repo-lint-checks).

`scripts/lib/repo-practices` implements the audit. Use `--merge-only` (via `scripts/check-merge-settings`) to run only the merge-queue subset.

| Check | Full audit | Merge-only | What it validates |
| --- | --- | --- | --- |
| Release Please squash settings | yes | yes | Repos with `release-please.yml` use squash-only merges on `main` |
| `protect-main` ruleset | yes | yes | Squash-only + Graphite App bypass or GitHub `merge_queue` on `refs/heads/main` when `merge-it`, GitHub MQ, or Release Please |
| Classic `main` protection | yes | — | CODEOWNERS reviews, CI contexts, push via Graphite only (org standard) |
| Graphite merge queue wiring | yes | yes | `merge-it` label (strict repos), `merge-mq` when present, `merged-pr-closer.yml`, `ci.yml` `gtmq_merge_*` skip, dependabot auto-merge when `dependabot.yml` exists |
| Workflow file extensions | yes | — | `.github/workflows/*` use `.yml` (not `.yaml`) |
| Branch cleanup workflows | yes | — | `cleanup-branch-on-merge.yml`, `cleanup-merged-branches.yml`, canonical `merged-pr-closer.yml` |
| License / copyright / CODEOWNERS | yes | — | Top-level LICENSE with copyright notice; `.github/CODEOWNERS` with org owner |
| Agent review cursor rule | yes | — | `.cursor/rules/pr-ship-and-review.mdc` + `.cursor/skills/ship-and-review/SKILL.md` reference `wait-for-agent-review` and reply-before-resolve |
| UV Python CVE check | yes | — | `uv.lock` + `pyproject.toml` repos require canonical `.github/workflows/cve-check.yml` |
| Python static CI job | yes | — | Python (`pyproject.toml` + ruff) repos run ruff check/format + typecheck in one `Python lint & format checks` job via `.github/ci/python-static`; no split `Ruff`/`Pyright`/`Mypy`/`Backend Lint` jobs; cutover aliases must gate on `needs.python-static.result == 'success'` (see `.cursor/rules/python-static-ci-job.mdc`) |
| `.cursor/rules` gitignore | yes | — | `.gitignore` must not block `.cursor/rules/` |
| Dependabot release age | yes | — | `cooldown` on every `dependabot.yml` updates entry (`release-age-defaults`) |
| pnpm release age | yes | — | `minimumReleaseAge` in `pnpm-workspace.yaml` when present |
| pnpm Corepack CI | yes | — | Exact `packageManager: pnpm@X.Y.Z` when lockfile exists; no `pnpm/action-setup` / `setup-node` `cache: pnpm`; use org composite `actions/setup-pnpm-corepack` (pin SHA on `main`; see section below) |
| `ci-secret-scan` gitleaks pin | yes* | — | Warn when `scripts/lib/ci-secret-scan` pins gitleaks behind the release-age-eligible version (*this repo only) |

`--suggest` prints remediation lines; `--apply-fix` queues candidate workflow/cursor-rule PRs via Graphite in the target repo clone.

See [`.cursor/skills/graphite/SKILL.md`](.cursor/skills/graphite/SKILL.md) for Graphite stacked PRs when `.github/stacking-tool` is `graphite`, and the **`merge-it`** label. This repo trials **`gh-stack`** — see [`.cursor/skills/gh-stack/SKILL.md`](.cursor/skills/gh-stack/SKILL.md) and [`.cursor/rules/stacking-tool.mdc`](.cursor/rules/stacking-tool.mdc).

### `protect-main` ruleset (required)

Any repo with **`merge-it`** (Graphite merge queue), **GitHub merge queue** (`merge_queue` rule), or **`release-please.yml`** must use the ruleset **`protect-main`** on `refs/heads/main`. Classic branch protection alone is **not** sufficient — the checker requires the ruleset.

| Ruleset rule | Purpose |
| --- | --- |
| `deletion` | Block branch deletion |
| `non_fast_forward` | Block force-push |
| `pull_request` with `allowed_merge_methods: ["squash"]` | Squash-only merges (Release Please + merge queues) |
| `bypass_actors`: Graphite App (`actor_id` **158384**, Integration, `always`) | Graphite MQ can land on `main` (Graphite MQ repos) |
| `merge_queue` with `merge_method: SQUASH` | Native GitHub merge queue (this repo) |

Classic branch protection on **`main`** is also required (org standard). It complements the ruleset — reviews, CI, and push restrictions — while **`protect-main`** enforces squash-only merges and either Graphite bypass or GitHub `merge_queue`.

| Classic setting | Graphite MQ repos | GitHub MQ (this repo) |
| --- | --- | --- |
| Required reviews | CODEOWNERS, dismiss stale; **0** approvals | same |
| Bypass (reviews) | **graphite-app**; **dependabot** when present; org owner | org owner (+ dependabot when present) |
| Push restrictions | **graphite-app** only | **none** (GitHub MQ lands merges) |
| Required status checks | All `ci.yml` job contexts except `guard`, `changed-files`, `secret-scan`, `workflow-lint` | same |
| Strict | `true` | same |
| Force-push / delete | disabled | same |
| `enforce_admins` | `false` (warn if enabled) | same |

Create or repair ruleset + classic settings with
`scripts/github-repo-lint --repo OWNER/NAME --apply-fix`. Run it from the target
repository clone when you want candidate workflow fixes emitted as a Graphite stack
under `.worktrees/repo-practices-candidate-fixes-wt`.

**`merge-mq`** is not the default enqueue label. Use it only when Graphite MQ for that repo is wired to **`merge-mq`**; otherwise use **`merge-it`** only.

### This repo: GitHub merge queue

**`repository-helpers`** uses **GitHub’s native merge queue** (not Graphite MQ):

- `protect-main` includes a `merge_queue` rule (`SQUASH`)
- `ci.yml` triggers on `merge_group` (and ignores `gh-readonly-queue/**` pushes)
- Merge with **Enable auto-merge** / **Merge when ready** (or `gh pr merge --auto --squash`)
- Do **not** use the `merge-it` label here — that enqueues Graphite MQ on other org repos

Disable this repo in [Graphite merge queue settings](https://app.graphite.com/settings/merge-queue) so Graphite does not also try to land PRs.

### Branch hygiene

| Workflow | Purpose |
| --- | --- |
| `cleanup-branch-on-merge.yml` | Delete the PR head branch when a PR merges |
| `cleanup-merged-branches.yml` | Daily sweep (+ `workflow_dispatch`) for merged and stale branches |

### CVE check workflow (uv Python)

Repos identified as uv Python projects (presence of `uv.lock` + `pyproject.toml` at the repo root) must include
`.github/workflows/cve-check.yml`, a scheduled daily `pip-audit` run that classifies JSON output (CVE vs transient
failure), retries only transient tool errors, and opens or updates a `security/cve` issue when vulnerabilities are
found. The job succeeds when CVEs are found **and** issue notification succeeds; it fails if pip-audit reports CVEs but
`gh issue` create/comment fails (so silent notification loss does not occur).

### pnpm / Corepack CI

Repos with `pnpm-lock.yaml` (root or `web/`) must:

1. Set an exact `"packageManager": "pnpm@X.Y.Z"` in the matching `package.json` (Corepack / CI SSOT).
   For nested apps (e.g. domesti-bot), put it in `web/package.json` and pass
   `working-directory: web` to the action.
2. Install pnpm in GitHub Actions via the org composite action
   [`actions/setup-pnpm-corepack`](actions/setup-pnpm-corepack/README.md) **after**
   `actions/setup-node`. Do **not** use `pnpm/action-setup` (especially not
   `version: latest` — floating tags have broken CI; see
   [pnpm/action-setup#276](https://github.com/pnpm/action-setup/issues/276)).
3. Do **not** set `cache: 'pnpm'` on `setup-node` — the composite action owns store-path
   discovery and `actions/cache`.

**Pin policy:** pin with a **full commit SHA that is on `main`** (a merge commit of this
repo), not a PR branch tip or other unmerged SHA. Example (current `main` tip as of the
merge of [#363](https://github.com/the-hcma/repository-helpers/pull/363)):

`cde3063aa1e030fcac59bbf215131a3bd25d7908`

Pin by SHA for supply-chain integrity (repository-helpers may be public; treat this as an
org composite action, not a “private action”). Dependabot does not always bump composite
action SHAs automatically — plan periodic pin updates when the helper changes.

**Path-filter gotcha:** CI path filters / “deps changed” gates that only watch
`package.json` and `pnpm-lock.yaml` will **skip** pnpm install/check jobs on
workflow-only adoption PRs (seen on [fpdf#464](https://github.com/the-hcma/fpdf/pull/464)).
When adopting the helper, include `.github/workflows/**` (or your equivalent workflow
paths) in those gates so the adoption PR actually runs install and check.

Canonical snippets (keep `pnpm install` in the same directory as the action input):

Root app:

```yaml
- uses: actions/checkout@v7.0.0
- uses: actions/setup-node@v6.4.0
  with:
    node-version: '24'
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
- run: pnpm install --frozen-lockfile
```

Nested app (`packageManager` under `web/`):

```yaml
- uses: actions/checkout@v7.0.0
- uses: actions/setup-node@v6.4.0
  with:
    node-version: '24'
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
  with:
    working-directory: web
- run: pnpm install --frozen-lockfile
  working-directory: web
```

See [`actions/setup-pnpm-corepack/README.md`](actions/setup-pnpm-corepack/README.md) for
inputs, caching, and consumer checklist.

### Merge settings and Graphite merge queue

With no `--repo`, the script audits the **current git repository** when run inside a clone (from `origin`). Outside a clone, discovery includes repositories that have `release-please.yml` or a **`merge-it`** label (use `--all` to scan every org repo).

```bash
scripts/check-merge-settings                      # current repo in a clone; else discover
scripts/check-merge-settings --repo OWNER/NAME
scripts/check-merge-settings --apply-fix          # patch Release Please squash settings only
```

### Release Please

Repositories with `/.github/workflows/release-please.yml` must use **squash merge only** on `main`. Merge commits duplicate changelog lines in release PRs (branch tip plus merge-commit body repeats the same conventional message). See [release-please#2476](https://github.com/googleapis/release-please/issues/2476).

| Setting | Value |
| --- | --- |
| Merge commits | disabled |
| Rebase merge | disabled |
| Squash merge | enabled |
| Squash commit message | `BLANK` (PR title only) |
| Squash commit title | `PR_TITLE` |
| Ruleset `protect-main` | `allowed_merge_methods`: `["squash"]` only |

### Graphite merge queue

The script verifies GitHub-side wiring (not Graphite app UI settings) when a **`merge-it`** label exists **and** the repo is not on GitHub’s native merge queue (`protect-main` `merge_queue` rule). When GitHub MQ is enabled, the checker validates `ci.yml` `merge_group` instead.

| Check | Other audited repos | This repo (`repository-helpers`) |
| --- | --- | --- |
| Label `merge-it` | required | not used (GitHub MQ) |
| Label `merge-mq` | required only when that label exists on the repo (MQ wired to `merge-mq`) | — |
| `merged-pr-closer.yml` detects `graphite-app` / merge queue | required | warn if missing |
| `ci.yml` skips `gtmq_merge_*` | required | n/a (GitHub MQ) |
| `ci.yml` `merge_group` trigger | required when GitHub MQ | required |
| `dependabot-auto-merge.yml` with `merge-it` when `dependabot.yml` exists | required | warn |
| `protect-main` bypass for Graphite App (`actor_id` **158384**) | required when Graphite MQ | n/a (use `merge_queue`) |
| Classic `main` protection (org standard) | required when `merge-it` or Release Please | required (no Graphite-only push restrictions) |

**Manual (Graphite MQ repos, not checked via `gh`):** enable the repo in [Graphite merge queue settings](https://app.graphite.com/settings/merge-queue), set merge strategy to **squash**, and wire enqueue labels (`merge-it`, or `merge-mq` when that repo uses it).

---

## Starting New Work

Before creating any branch or writing any code, run the session initialization script from the repository root:

```bash
scripts/dev/start-development
```

This script:
- Prunes stale worktrees and merged branches
- Syncs Graphite (`gt sync`)
- Creates a new worktree under `.worktrees/` (or resumes an existing one with `--resume`)

Do **not** manually create worktrees or run `gt sync` separately — `start-development` is the single entry point for all new work.

After `start-development` finishes, **`cd` into the stack worktree** (`.worktrees/<stack-name>-wt`) before any other work. Do not stay in the primary clone.

### Main worktree is off-limits (agents)

The **primary clone** (repo root — first entry in `git worktree list`, usually on branch `main`) is the **main worktree**. Treat it as **read-only** unless the user explicitly authorizes touching it in the current conversation.

**Never on the main worktree** (without explicit user authorization):

- Edit, create, or delete source files, config, or lockfiles
- Run dependency installs, tests, builds, or formatters
- Run `dep-updater` with `--dir` pointing at the primary clone (it may fast-forward `main` and mutate git state)
- Run `gt create`, `gt modify`, `gt submit`, `gt sync`, `gt restack`, or other Graphite/git write operations
- Leave uncommitted changes, stray branches, or detached HEAD state

**Always** do implementation, investigation that mutates state, and validation in a **stack worktree** under `.worktrees/<stack-name>-wt`. Pass that path to tools (`--dir`, `cd`, etc.).

`start-development` may update the main worktree for environment sync only; that is not permission to work there. If you need to inspect `main` without changing it, use read-only commands (`git log`, `git show`, `gh pr view`) or a **detached temporary worktree** — not the primary clone.

When `start-development` is invoked by an AI agent, it must be run **non-interactively** (never prompting):

```bash
scripts/dev/start-development --worktree <stack-name> --no-interactive
```

Use `--refresh` to pull the latest `main` and ensure the service is running without opening a new worktree:

```bash
scripts/dev/start-development --refresh
```

## Worktree-aware Scripts

`setup-service` and `scripts/on-deploy` are **worktree-aware**: unit templates in
`etc/systemd/`, `@@REPO_DIR@@` substitution in the generated unit file, and the
`on-deploy` hook itself are resolved from whichever worktree the script is invoked
from. Calling `setup-service` from a feature worktree therefore deploys that
worktree's code — this is the primary mechanism for testing feature branches locally.

- **`DEPLOYED_COMMIT`:** `setup-service` injects `Environment=DEPLOYED_COMMIT=<HEAD>` into the generated systemd unit (no template change required). The running commit is read from the service process environment, not `git HEAD` at the process cwd. If `DEPLOYED_COMMIT` is missing on the running process, missing from the installed unit, or differs from the current checkout, treat the deploy as stale: run `on-deploy` and restart conservatively.
- **Service name** is derived from the git remote URL (not the directory name), so it is stable across all worktrees.
- **`on-deploy`** must use `BASH_SOURCE[0]` to locate itself and must `cd` into its own directory's parent — never hardcode absolute paths or assume a fixed working directory.
- **`.env` and SQLite database for feature worktrees**: services that use SQLite in development must handle two concerns when `on-deploy` runs from a feature worktree:
  1. **Copy the primary `.env`** so that all accumulated settings (extra `ALLOWED_HOSTS` entries, `SECRET_KEY`, etc.) carry over without needing to be re-entered.
  2. **Set `DATABASE_URL`** pointing at the primary worktree's `db.sqlite3` so all worktrees share the same live data.
  
  Detect worktree status before any `.env` work, copy if needed, then handle `DATABASE_URL`. Example pattern:
  ```bash
  primary_dir="$(git -C "$repo_dir" worktree list --porcelain | awk 'NR==1{print $2}')"
  env_file="$repo_dir/.env"
  primary_env="$primary_dir/.env"
  if [[ "$repo_dir" != "$primary_dir" ]] && [[ -f "$primary_env" ]]; then
      cp "$primary_env" "$env_file"
      echo "  Copied .env from primary worktree (settings carry over)."
  fi
  # ... normal .env setup (will see existing settings and skip updates) ...
  if [[ "$repo_dir" != "$primary_dir" ]]; then
      db_url="sqlite:///${primary_dir}/db.sqlite3"
      if ! grep -q '^DATABASE_URL=' "$env_file"; then
          echo "DATABASE_URL=${db_url}" >> "$env_file"
      elif ! grep -qF "DATABASE_URL=${db_url}" "$env_file"; then
          sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${db_url}|" "$env_file"
      fi
      echo "  Using database from main worktree: ${primary_dir}/db.sqlite3"
  fi
  ```

## on-deploy hooks

Service repositories install via `scripts/setup-service` and optionally implement `scripts/on-deploy`. Shared dependency logic lives in **`scripts/lib/on-deploy-deps`** — do not copy staleness checks into each repo.

### Exit codes (required)

| Code | Meaning |
|------|---------|
| `0` | Steps ran; unit must restart |
| `1` | No change; restart optional |
| `2+` | Error; abort deploy |

### Required behaviour

1. Resolve `repo_dir` from `BASH_SOURCE[0]`; never assume `$PWD`.
2. Load the library via `on-deploy-deps-bootstrap` (see `docs/on-deploy-deps-load.snippet` — path-resolve and `source` the bootstrap file, then `on_deploy_deps_load_library "$repo_dir"`).
3. **Skip decision:** if caching “already deployed at commit X”, also call `on_deploy_deps_python_env_stale "$repo_dir"` and, when applicable, `on_deploy_deps_pnpm_modules_stale "$repo_dir" [subdir]`. Do not skip when either returns stale (exit status `0`).
4. **Bootstrap:** `on_deploy_deps_bootstrap_python_venv "$repo_dir"` before `uv run` when the service uses uv.
5. **Full deploy path:** `on_deploy_deps_sync_python_frozen "$repo_dir"`; `on_deploy_deps_install_pnpm_frozen "$repo_dir" [subdir]` before `pnpm run build`; then repo-specific migrations, bundles, and smoke imports.
6. Do not invoke bare `python3` for utility work before the venv exists (consuming services may document an exception after `uv sync` in their own AGENTS.md).

### Library resolution order

1. `$REPOSITORY_HELPERS_DIR/scripts/lib/on-deploy-deps`
2. `$repo_dir/../repository-helpers/scripts/lib/on-deploy-deps`
3. `$HOME/work/ai/repository-helpers/scripts/lib/on-deploy-deps`

---

## Commits, Stacking & Pull Requests

> See [`.cursor/skills/graphite/SKILL.md`](.cursor/skills/graphite/SKILL.md) for the full Graphite workflow reference when `.github/stacking-tool` is `graphite` (branch naming, stack creation, navigation, submission, troubleshooting, and advanced rebasing). For this repo (`gh-stack`), see [`.cursor/skills/gh-stack/SKILL.md`](.cursor/skills/gh-stack/SKILL.md) and [`.cursor/rules/stacking-tool.mdc`](.cursor/rules/stacking-tool.mdc).

- Stacking backend is selected by `.github/stacking-tool` (`graphite` or `gh-stack`). Prefer **`scripts/dev/submit-stack`** (dispatches via `scripts/lib/stacking-tool`).
- Never work directly on `main`. Create stack layers with `gh stack init` / `gh stack add` when the marker is `gh-stack`, or `gt create` when it is `graphite`.
- Keep each branch in the stack focused on exactly one logical change. Stacks should map 1-to-1 with milestones or sub-tasks from [dep-updater.plan.md](./dep-updater.plan.md).
- Sync via `scripts/dev/start-development` (marker-aware). For `gh-stack`, use `gh stack sync` / `gh stack rebase` as needed; for Graphite, `gt sync` / `gt restack`.
- **Before opening/submitting a PR**, run **`scripts/dev/pre-pr-checks`** from your feature worktree (or use **`scripts/dev/submit-stack`**). Do not submit without passing pre-pr-checks first.
- `pre-pr-checks` mirrors CI: `bash -n`, `shellcheck -S info` (all `scripts/*`, `scripts/dev/*`, `scripts/lib/*`, `tests/*`, `tests/lib/*`), and **every** `tests/*.test` must pass. It also verifies the **primary worktree** is unchanged when checks finish (auto-stash/restore any pre-existing local changes on main).
- Before submitting a PR, ensure it has a useful description (at minimum: **Summary** + **Test plan**).
- PRs must be **published (not draft)** so reviewers see them normally. Prefer `scripts/dev/submit-stack` for non-interactive submit (implies `--publish`).
- To merge a PR in **this** repo: enable auto-merge / Merge when ready so GitHub’s merge queue lands it (`gh pr merge --auto --squash`). Do **not** use `merge-it` here. **Other org repos** still use `gh pr edit <number> --add-label merge-it` for Graphite MQ. **Exception:** `dep-updater` batch runs (`--batch`, including daily `--batch --all`) may use `gh pr merge --auto --squash` after CI passes (`--merge-via gh`, the batch default); `--auto` lets GitHub wait for required checks / the merge queue.
- Follow **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
- Each commit must pass all CI checks (see below) before being pushed.
- Never merge a PR until **all checks have run and are green** (no skipped required checks).
- Keep commits focused. One logical change per commit.
- PR descriptions must reference the relevant milestone from [dep-updater.plan.md](./dep-updater.plan.md).
- Before starting a new PR or branch, confirm the current PR is either merged or that all CI checks pass. Never start new work on a broken base.

### Agent review after submit

After every push, **`scripts/dev/post-pr-submission-checks --pr <n>`** must pass (CI green on the PR head). `scripts/dev/submit-stack` and `scripts/dev/ship-and-review` invoke this by default.

When CI is green, follow **`.cursor/skills/ship-and-review/SKILL.md`** (deep playbook) and the thin contract **`.cursor/rules/pr-ship-and-review.mdc`**:

1. Prefer **`./scripts/wait-for-agent-review loop --pr <n>`** (or `scripts/dev/ship-and-review` from submit).
2. On exit **3**, triage feedback: fix → **`reply-thread`** / **`reply-comment`** → **`resolve-thread`** / **`resolve-comment`** — never resolve without replying first.
3. When `check` reports `complete_ready: true`, run **`./scripts/wait-for-agent-review complete --pr <n>`** (requires **agent sign-off** on the current head).
4. Configure `~/.config/agent-review.env` from `etc/agent-review.env.example`.

See the Skill for CodeRabbit on_push policy, early-complete loop semantics, per-agent quota fallback, and exit codes (**`scripts/wait-for-agent-review --help`** is the SSOT).

**Copilot timeline failures:** credit exhaustion sometimes appears only as a PR timeline event
`copilot_work_finished_failure` (GitHub App `copilot-swe-agent`) with no issue comment or review
body. Quota observe scans that timeline event for the local calendar day. Non-quota work failures
of the same event type also mark Copilot exhausted for the day (acceptable for skip caches).

---

## Shell Script Conventions

- **No `.sh` extension.** Scripts live in `scripts/` and test harnesses in `tests/`. The shebang line declares the interpreter.
- **`readonly`** must be used for every script-level variable that is assigned once and never modified. Declare and assign on separate lines to avoid SC2155:
  ```bash
  var="$(some_command)"
  readonly var
  ```
- **Non-exported variables must be lowercase.** Uppercase is reserved for exported environment variables (`export FOO=bar`). Script-level constants, loop variables, and function locals all use `snake_case`.
- **Use `local` for all function-scoped variables.** For parameters or literal assignments that won't change, prefer `local -r`. For command substitutions, always declare separately:
  ```bash
  my_func() {
    local -r mode="${1:-default}"   # parameter — safe to combine
    local result                    # command substitution — declare separately
    result="$(some_command)"        # assign after to preserve exit code
  }
  ```
- Prefer `readonly` for **script-level** variables/constants, and `local -r` for **function-local** constants. `readonly` is global in scope; using it inside a function will leak state outside the function, so `local -r` (or `declare -r`) is the correct way to express “read-only, but scoped to this function”.
- **Never declare `local -r` or plain `local` inside a loop body.** Hoist all `local` declarations to the top of the function. `local -r` inside a loop will crash on the second iteration with "readonly variable" because `local -r` both declares and sets, and re-entering the loop tries to re-declare an already-readonly name.
- Do not use `A && B || C` as an if-then-else substitute (SC2015). Use a proper `if/then/else` block.
- **Prefer long-form flags** for all command invocations (e.g. `--follow=name` not `-f`, `--all` not `-a`). Short flags are allowed only when no long form exists.
- **Cron environment is minimal.** Any script designed to run under cron must not assume interactive shell init (e.g. PATH modifications that make `gt` visible). Prefer one (or both) of:
  - Setting a safe PATH at the top of the script (include at least `${HOME}/.local/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`).
  - Documenting a cron pattern like `bash -lc '<command>'` when shell init is required.
  
  Additionally, avoid patterns where failures are silently dropped under cron (e.g. redirecting tool stderr to `/dev/null` without surfacing errors elsewhere). If a cron job can fail to scan/act due to missing tooling, it must emit an observable report (email/log) rather than exiting 0 silently.

---

## Security

- All file paths received from the CLI must be validated and resolved with `realpath`/`readlink -f` before any file system operation. Reject paths that escape the working directory.
- No dynamic `eval` or command construction from user-controlled strings.
- Do not log, store, or transmit credential tokens beyond what is needed to invoke `gh`/`gt`.

---

## CI Checks (all must pass)

Run locally via **`scripts/dev/pre-pr-checks`** before every PR (same commands as CI):

```
scripts/dev/pre-pr-checks            # preferred: all checks + main worktree guard
# or manually:
bash -n scripts/* scripts/dev/* scripts/lib/* tests/* tests/lib/*
shellcheck -S info scripts/* scripts/dev/* scripts/lib/* tests/* tests/lib/*
actionlint .github/workflows/*.yml scripts/lib/repo-practices-workflows/*.yml
bash tests/*.test                    # every test harness
```

No PR may be merged with a failing CI check. No exceptions.
