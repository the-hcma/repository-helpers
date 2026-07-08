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
| Agent review | `scripts/wait-for-agent-review`, `scripts/trigger-agent-review` | PR review loop, triage, approve, operator email. |
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
- **CVE / security bumps can land early.** Dependabot **security** PRs ignore the version-update `cooldown` and may open immediately. **dep-updater** skips the 9-day gate when `npm audit` or `pip-audit` reports a CVE fix (`npm_pkg_has_cve_fix_in_audit` / `py_pkg_has_cve_fix_in_audit`). Routine **version-update** PRs from Dependabot still wait 10 days (weekly scan + cooldown); dep-updater usually lands those first — close redundant Dependabot version PRs when appropriate.
- **pnpm grandfathering (cutover only).** When enabling `minimumReleaseAge` on a repo with an existing lockfile, run `scripts/grandfather-pnpm-release-age` once to write `pnpm-workspace.yaml` with `minimumReleaseAgeExclude: ["*"]` so the current lockfile keeps passing CI under pnpm 11.1.3+. No registry file or prune step—**forward** bumps are gated by dep-updater (9 days) and Dependabot cooldown (10 days).
- **GitHub Actions pins follow their own style.** `@v6` (major-only) bumps to the latest release semver when newer—patch within the same major (`v6` → `v6.0.2`) or major jump (`v7` → `v8.1.0`), matching Dependabot. `@v1.7.12` / `@0.36.0` (full semver) is bumped on any newer release. The `v`-prefix style of the existing pin is preserved. Commit-SHA pins (`@abc1234...`) and local actions (`./path`) are never touched.
- **Wait timeouts must be machine-parseable.** Any long-running wait loop (CI gating, merge polling, PR number discovery, etc.) must, on timeout, emit **one** concise line starting with `ERROR: WAIT_TIMEOUT ...` and then fail. Avoid multi-line timeout chatter — batch runs (`--batch --all`) postprocess these lines into end-of-run actionable summaries.

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

See [GRAPHITE.md](./GRAPHITE.md) for stacked PRs, the merge queue, and the **`merge-it`** label.

### `protect-main` ruleset (required)

Any repo with **`merge-it`** (Graphite merge queue) or **`release-please.yml`** must use the ruleset **`protect-main`** on `refs/heads/main`. Classic branch protection alone is **not** sufficient — the checker requires the ruleset.

| Ruleset rule | Purpose |
| --- | --- |
| `deletion` | Block branch deletion |
| `non_fast_forward` | Block force-push |
| `pull_request` with `allowed_merge_methods: ["squash"]` | Squash-only merges (Release Please + Graphite MQ) |
| `bypass_actors`: Graphite App (`actor_id` **158384**, Integration, `always`) | Merge queue can land on `main` |

Classic branch protection on **`main`** is also required (org standard). It complements the ruleset — reviews, CI, and push restrictions — while **`protect-main`** enforces squash-only merges and ruleset-level Graphite bypass.

| Classic setting | Value |
| --- | --- |
| Required reviews | CODEOWNERS (`require_code_owner_reviews`), dismiss stale; **0** GitHub approvals (Graphite owns review flow) |
| Bypass (reviews) | **graphite-app**; **dependabot** when `dependabot.yml` exists; org owner login (emergency bypass) |
| Push restrictions | **graphite-app** only (merge queue lands on `main`) |
| Required status checks | All `ci.yml` job contexts except `guard`, `changed-files`, `secret-scan`, `workflow-lint` |
| Strict | `true` (branch must be up to date) |
| Force-push / delete | disabled |
| `enforce_admins` | `false` (warn if enabled) |

Create or repair ruleset + classic settings with
`scripts/github-repo-lint --repo OWNER/NAME --apply-fix`. Run it from the target
repository clone when you want candidate workflow fixes emitted as a Graphite stack
under `.worktrees/repo-practices-candidate-fixes-wt`.

**`merge-mq`** is not the default enqueue label. Use it only when Graphite MQ for that repo is wired to **`merge-mq`**; otherwise use **`merge-it`** only.

### Branch hygiene

| Workflow | Purpose |
| --- | --- |
| `cleanup-branch-on-merge.yml` | Delete the PR head branch when a PR merges |
| `cleanup-merged-branches.yml` | Daily sweep (+ `workflow_dispatch`) for merged and stale branches |

### CVE check workflow (uv Python)

Repos identified as uv Python projects (presence of `uv.lock` + `pyproject.toml` at the repo root) must include
`.github/workflows/cve-check.yml`, a scheduled daily `pip-audit` run (via `uv run --with pip-audit pip-audit --skip-editable`).

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

The script verifies GitHub-side wiring (not Graphite app UI settings) when a **`merge-it`** label exists:

| Check | Other audited repos | This repo (`repository-helpers`) |
| --- | --- | --- |
| Label `merge-it` | required | required |
| Label `merge-mq` | required only when that label exists on the repo (MQ wired to `merge-mq`) | — |
| `merged-pr-closer.yml` detects `graphite-app` / merge queue | required | warn if missing |
| `ci.yml` skips `gtmq_merge_*` | required | warn if missing |
| `dependabot-auto-merge.yml` with `merge-it` when `dependabot.yml` exists | required | warn |
| `protect-main` bypass for Graphite App (`actor_id` **158384**) | required when `merge-it` or Release Please | warn |
| Classic `main` protection (org standard) | required when `merge-it` or Release Please | warn |

**Manual (not checked via `gh`):** enable the repo in [Graphite merge queue settings](https://app.graphite.com/settings/merge-queue), set merge strategy to **squash**, and wire enqueue labels (`merge-it`, or `merge-mq` when that repo uses it).

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

> See [GRAPHITE.md](./GRAPHITE.md) for the full Graphite workflow reference (branch naming, stack creation, navigation, submission, troubleshooting, and advanced rebasing).

- This project uses **Graphite** (`gt`) for branch stacking.
- All work is done in stacked branches via `gt create`, `gt modify`, and `gt submit`.
- Never work directly on `main`. Always create a stack branch: `gt create -m "feat: description"`.
- Keep each branch in the stack focused on exactly one logical change. Stacks should map 1-to-1 with milestones or sub-tasks from [dep-updater.plan.md](./dep-updater.plan.md).
- Sync regularly: `gt sync` before starting new work; `gt restack` after upstream changes land.
- Submit stacks with `gt submit` — do not open PRs manually via the GitHub UI.
- **Before opening/submitting a PR**, run **`scripts/dev/pre-pr-checks`** from your feature worktree (or use **`scripts/dev/submit-stack`**, which runs checks then `gt submit --publish --no-interactive`). Do not run bare `gt submit` without passing pre-pr-checks first.
- `pre-pr-checks` mirrors CI: `bash -n`, `shellcheck -S info` (all `scripts/*`, `scripts/dev/*`, `scripts/lib/*`, `tests/*`, `tests/lib/*`), and **every** `tests/*.test` must pass. It also verifies the **primary worktree** is unchanged when checks finish (auto-stash/restore any pre-existing local changes on main).
- Before submitting a PR, ensure it has a useful description (at minimum: **Summary** + **Test plan**).
- PRs must be **published (not draft)** so reviewers see them normally. Prefer `scripts/dev/submit-stack` for non-interactive submit (implies `--publish`).
- To merge a PR, add the `merge-it` label: `gh pr edit <number> --add-label merge-it`. Do not use `gh pr merge` manually. **Exception:** `dep-updater` batch runs (`--batch`, including daily `--batch --all`) may use `gh pr merge --auto --squash` after CI passes (`--merge-via gh`, the batch default); `--auto` lets GitHub wait for required branch checks instead of merging immediately.
- Follow **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
- Each commit must pass all CI checks (see below) before being pushed.
- Never merge a PR until **all checks have run and are green** (no skipped required checks).
- Keep commits focused. One logical change per commit.
- PR descriptions must reference the relevant milestone from [dep-updater.plan.md](./dep-updater.plan.md).
- Before starting a new PR or branch, confirm the current PR is either merged or that all CI checks pass. Never start new work on a broken base.

### Agent review after submit

After every push, **`scripts/dev/post-pr-submission-checks --pr <n>`** must pass (CI green on the PR head). It waits for GitHub Actions and, on failure, prints **`==> CI failure details for coding agent`** with filtered job log excerpts so the agent can fix and re-push. `scripts/dev/submit-stack` invokes this by default; do not skip CI monitoring unless the user opts out (`--no-wait-ci`).

When CI is green, run the **agent review loop** documented in **`.cursor/rules/pr-ship-and-review.mdc`**:

1. Prefer **`./scripts/wait-for-agent-review loop --pr <n>`** (or `scripts/dev/ship-and-review` from submit).
2. On exit **3**, triage each feedback item (inline thread or top-level issue comment): fix → **`reply-thread`** / **`reply-comment`** → **`resolve-thread`** / **`resolve-comment`** — never resolve without replying first. Use **`list-feedback`** to see pending items.
3. **`./scripts/wait-for-agent-review complete --pr <n>`** when `check` reports `complete_ready`, or let **`loop`** exit **0** when nothing is outstanding (no pending feedback, no in-flight agent wait, CodeRabbit idle).
4. Configure `~/.config/agent-review.env` from `etc/agent-review.env.example`.

#### Early-complete loop and per-agent quota skip

- **Nothing outstanding:** after all threads are addressed, CI is green, and the PR is merge-ready,
  `loop` completes as soon as it is not waiting on a requested Copilot/Bugbot review and CodeRabbit
  is idle. `cmd_complete_idle` (early) approves and emails — **without** requiring Copilot
  **“generated no new comments”**. `AGENT_REVIEW_CYCLE_TIMEOUT` is retained for compatibility only.
- **`AGENT_REVIEW_PR_TIMEOUT`** (default **12h**): non-convergence cap when review cycles keep
  iterating without reaching early-complete; exit **6** triggers give-up.

Per-agent daily quota caches skip review requests for exhausted agents (CodeRabbit, Copilot, Bugbot)
and probe the next agent in `AGENT_REVIEW_QUOTA_FALLBACK_CHAIN` (see
`.cursor/rules/pr-ship-and-review.mdc`).

Configure `~/.config/agent-review.env` from `etc/agent-review.env.example`. Set `AGENT_REVIEW_AGENT=copilot` or another supported profile under `scripts/lib/agent-review-profiles/`.

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
