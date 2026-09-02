# AGENTS.md — Ground Rules for repository-helpers

This file defines the non-negotiable standards for all contributors (human or AI) working on this codebase. Every change must comply with these rules before it is considered complete.

---

## Session startup

At the **start of every agent session**, before acting from assumed conventions:

1. Read this `AGENTS.md` in full.
2. Read every rule under `.cursor/rules/*.mdc` with `alwaysApply: true` in its
   front matter, plus any rule whose `globs` match files you will touch.
   `AGENTS.md` and `.cursor/rules/` together are the contract — neither alone is complete.

`CLAUDE.md` (a `@AGENTS.md` import) and `.github/copilot-instructions.md` are thin
shims so Claude Code and Copilot reach this same guidance — do not put rules in them.

---

## Utilities overview

Top-level scripts (see [README.md](./README.md) for operator-oriented summaries):

| Area | Script | Role |
| --- | --- | --- |
| Dependencies | `scripts/dep-updater` | Create stacked dependency-update PRs (npm, Python, Rust, Actions). |
| Batch automation | `scripts/dep-updater-batch-run` | Daily `--batch --all` across a scan root; email report. |
| Dep-updater CI | `scripts/dep-updater-ci-org-dry-run` | Clone org repos and `--batch --all --dry-run` for PR validation. |
| Repo practices | `scripts/github-repo-lint` | Audit/onboard org repos (merge queue, `protect-main`, workflows). |
| Secret audit | `scripts/secret-audit` | TruffleHog deep scan (full git history); intake marker (see [docs/secret-audit-trufflehog.md](./docs/secret-audit-trufflehog.md)). |
| Secret audit batch | `scripts/secret-audit-batch-run` | Daily org TruffleHog sweep; email report (systemd timer). |
| Merge settings | `scripts/check-merge-settings` | Thin wrapper (merge + GitHub MQ only). |
| Lockfile drift | `scripts/check-lockfile-drift` | Compare lockfiles to registry constraints. |
| Credentials | `scripts/check-token-expiry` | Preflight a CI environment PAT's expiry; warn before it dies. |
| pnpm cutover | `scripts/grandfather-pnpm-release-age` | One-time `minimumReleaseAgeExclude` for existing lockfiles. |
| Systemd | `scripts/setup-service`, `scripts/setup-github-repo-lint`, `scripts/setup-secret-audit`, `scripts/show-services` | Install timers/units; status summary. |
| Deploy hook | `scripts/on-deploy` | Example hook; consumer repos implement their own. |
| Agent review | `scripts/wait-for-agent-review`, `scripts/trigger-agent-review` | PR review loop, triage, operator email (no self-approve). |
| Dev workflow | `scripts/dev/start-development` | Worktree + Graphite sync entry point. |
| Dev workflow | `scripts/dev/pre-pr-checks` | Detect-first local CI gates (bash + Python/TS/Rust when present; secret-scan when adopted). |
| Dev workflow | `scripts/dev/secret-scan` | Local gitleaks via canonical `ci-secret-scan` (same as CI / pre-pr secret-scan job). |
| Dev workflow | `scripts/dev/submit-stack` | `pre-pr-checks` → `gt submit` → `post-pr-submission-checks`. |
| Dev workflow | `scripts/dev/approve-pending-deployments` | Approve WAITING environment jobs on the operator's behalf. |
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
 `pip`, `uv`, `poetry`, `cargo` + `cargo-outdated` + the `clippy` component) as
 optional callees. Rust is required for any repo dep-updater detects as a Cargo
 project — it shells out to `cargo outdated` and `cargo add`, and the Rust post-bump
 clippy recovery invariant below assumes a toolchain.

 ```bash
  rustup component add clippy             # absent under rustup's minimal profile
  cargo install cargo-outdated --locked   # same line CI uses
  ```

 Provisioning notes for the batch host:
 - apt's Rust is too old for current `cargo-outdated` — install via rustup. On
 Debian/Ubuntu `build-essential pkg-config libssl-dev` are also needed for
 `openssl-sys` / `libgit2-sys`.
 - `~/.cargo/bin` is not on a systemd/cron `PATH` by default, so a timer-run batch
 can still report the tool missing after a successful interactive install (see
 `tooling_path_ensure_gnu_userland` / the cron bootstraps).

 A host missing one of these no longer fails the whole run: `--batch --all` skips
 those repos and reports them under **Skipped (missing tooling)** in the email
 (see the batch-all invariant below).
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

- **Stacking backend follows `.github/stacking-tool`.** Consumer repos declare `graphite` or `gh-stack` in `.github/stacking-tool`. dep-updater uses `gt track` / `gt submit` for Graphite and `gh stack submit` for gh-stack. **When the marker is absent, dep-updater selects `gh-stack`** (logged as the missing-marker default). Explicit `graphite` keeps the Graphite path; invalid markers still fail. Other helpers (`github-repo-lint --apply-fix`, `start-development`) still use org default `graphite` when the marker is missing. Merge enqueue uses `gh pr merge --auto --squash` (GitHub native merge queue — org default). Leftover `merge-it` / `merge-mq` labels are ignored and must not select Graphite MQ enqueue.
- **Never introduce `==` pins (Python).** dep-updater always writes `>=` floor constraints when bumping a Python dependency. It must never lock a package to an exact version.
- **Respect existing pins for pip / pipenv / poetry.** For these ecosystems, `==` signals a deliberate user decision to lock a specific version. dep-updater skips those packages entirely (`py_is_pinned`).
- **uv `==` pins are not treated as intentional freezes.** dep-updater updates them and promotes the constraint to `>=` on bump. The transitive constraint check (`uv pip install --dry-run`) still gates upgrades that would violate real transitive constraints.
- **npm exact pins are updated in place, not skipped.** An exact version in `package.json` (e.g. `"vitest": "4.1.4"`) is bumped to the new version while preserving the exact style (no promotion to `^`). This matches Dependabot's behaviour. Local/git references (`workspace:`, `file:`, `link:`, `git`) are still skipped.
- **Release age (dep-updater 9 days, Dependabot 10 days).** dep-updater does not propose bumps to registry versions published less than **9 days** ago (`scripts/lib/release-age-defaults`). Dependabot `cooldown` on managed repos is **one day longer** (10 days) so dep-updater lands updates first. When the target project sets a higher `minimumReleaseAge` in `pnpm-workspace.yaml`, the larger value is used for npm. The same 9-day gate applies to Python/PyPI and GitHub Actions bumps.
- **npm picks the newest eligible version, not only dist-tags.latest.** When `dist-tags.latest` is still inside the release-age window, dep-updater walks stable registry versions (newest-first) and proposes the newest one that passes release-age and closure checks — matching Dependabot cooldown behaviour and GitHub Actions `_gha_pick_eligible_new_ref`.
- **Platform-marked uv deps are discovered from `uv.lock`, not the environment.** Deps carrying a PEP 508 environment marker that excludes the batch host (e.g. `sys_platform == 'darwin'` under the Linux timer) never install there, so `uv pip list --outdated` cannot see them and the `>=` floor scan skips them as uninstalled. `py_uv_marker_gated_rows` seeds them from the **universal** `uv.lock` (which records every marker branch) so `==`/`>=` specifiers in `[project.optional-dependencies]` and `[dependency-groups]` still get bumped. These candidates also skip `py_uv_probe_transitive_upgrade` — that dry-run is current-platform only and would always reject them — and are gated by the batch `uv lock` filter instead. No macOS runner is required: `uv lock` resolves darwin-only upgrades from Linux (repository-helpers#532).
- **Python (uv) picks the newest eligible version, including floor-only bumps.** When `uv pip list --outdated` latest or a stale `>=` floor’s installed target is still inside the release-age window, `py_pick_eligible_new_version` walks PyPI (newest-first) and proposes the newest age-eligible stable version newer than the current floor/installed baseline — same idea as npm/GHA (e.g. raise `ruff>=0.15.17` to `>=0.15.21` when `0.15.22` is too new).
- **TypeScript major bumps are held.** dep-updater does not propose `typescript` major upgrades (e.g. 6.x → 7.x). TypeScript 7 removed the programmatic APIs that `typescript-eslint` needs, so majors break ESLint CI until upstream supports them. Same-major patch/minor bumps still land; CVE-driven majors are still allowed.
- **CVE / security bumps can land early.** Dependabot **security** PRs ignore the version-update `cooldown` and may open immediately. **dep-updater** skips the 9-day gate when `npm audit` or `pip-audit` reports a CVE fix (`npm_pkg_has_cve_fix_in_audit` / `py_pkg_has_cve_fix_in_audit`). Routine **version-update** PRs from Dependabot still wait 10 days (weekly scan + cooldown); dep-updater usually lands those first — close redundant Dependabot version PRs when appropriate.
- **pnpm grandfathering (cutover only).** When enabling `minimumReleaseAge` on a repo with an existing lockfile, run `scripts/grandfather-pnpm-release-age` once to write `pnpm-workspace.yaml` with `minimumReleaseAgeExclude: ["*"]` so the current lockfile keeps passing CI under pnpm 11.1.3+. No registry file or prune step—**forward** bumps are gated by dep-updater (9 days) and Dependabot cooldown (10 days).
- **GitHub Actions pins follow their own style.** `@v6` (major-only) bumps to the latest release semver when newer—patch within the same major (`v6` → `v6.0.2`) or major jump (`v7` → `v8.1.0`), matching Dependabot. `@v1.7.12` / `@0.36.0` (full semver) is bumped on any newer release. The `v`-prefix style of the existing pin is preserved. Commit-SHA pins (`@abc1234...`) and local actions (`./path`) are never touched.
- **Rust post-bump clippy recovery.** After `cargo add` bumps (batch or single), dep-updater runs `cargo clippy --all-targets -- -D warnings`. On failure it tries `cargo clippy --fix` (mechanical suggestions only) and re-checks. Unrecovered failures log machine-parseable `ERROR: RUST_CLIPPY_RECOVER_FAILED`, revert the Rust bump (keeping other ecosystems), and continue (repository-helpers#433).
- **Missing host tooling is a skip in `--batch --all`, not a repo failure.** Absent ecosystem tooling is a property of the host, not the repository, so `check_ecosystem_prereqs` exits **`dep_updater_exit_missing_tooling` (3)** after logging one `ERROR: MISSING_ECOSYSTEM_TOOLING tools=<list>` line instead of `die`ing with 1. A `--batch --all` parent treats exit 3 as `[batch-all] Skipping <repo>: missing host tooling (<tools>)`: `worst_exit` is unchanged, the ephemeral clone is **removed** (the fix is `cargo install` on the host, so there is nothing in the clone to repair), and the repos appear under **Skipped (missing tooling)** in the `dep-updater-batch-run` email so the provisioning gap stays visible. **Single-repo runs still fail loudly** — an operator who pointed dep-updater at one repo wants the error, not a silent skip. Non-tooling failures keep their existing exit code, clone retention, and Failed section (repository-helpers#535).
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

Run **`scripts/github-repo-lint`** to audit or onboard a GitHub repository against org conventions (merge settings, GitHub native merge queue, branch cleanup, Dependabot auto-merge, and dependency release-age policy: Dependabot `cooldown` and pnpm `minimumReleaseAge` per `scripts/lib/release-age-defaults`).

```bash
scripts/github-repo-lint --new-repo --repo OWNER/NAME       # checklist + SUGGEST hints
scripts/github-repo-lint --repo OWNER/NAME --suggest        # audit one repo with remediation lines
scripts/github-repo-lint --all --org the-hcma               # every repo in the org
scripts/github-repo-lint --apply-fix --repo OWNER/NAME      # patch settings + candidate workflow PRs
```

CI (`.github/workflows/github-repo-lint.yml`) runs the same `--all --strict-onboarding --compact` audit only when a PR changes `.cursor/rules/**`, `.github/workflows/github-repo-lint.yml`, `scripts/github-repo-lint`, `scripts/lib/repo-practices-cursor/**`, or `scripts/lib/repo-practices`. Path filters skip the workflow (and the approval prompt) otherwise. When it does run, environment **`github-repo-lint`** waits to unlock **`REPO_LINT_TOKEN`**.

CI (`.github/workflows/dep-updater.yml`) runs `scripts/dep-updater-ci-org-dry-run` (clone org repos, then `dep-updater --batch --all --dry-run --include-private`) only when a PR changes `.github/workflows/dep-updater.yml`, `scripts/dep-updater`, `scripts/dep-updater-batch-run`, `scripts/dep-updater-ci-org-dry-run`, `scripts/dep-updater-notifier`, or `scripts/lib/release-age-defaults`. Path filters skip the workflow (and the approval prompt) otherwise. When it does run, environment **`dep-updater`** waits to unlock **`DEP_UPDATER_TOKEN`** (same access as local `gh`; set from `gh auth token`).

**Coding agents MUST approve those waiting environments on the operator's behalf.** `gh` is the authenticated operator; do not wait for a human to click Approve in the Actions UI. `scripts/dev/post-pr-submission-checks` does this while waiting for CI. To approve immediately:

```bash
scripts/dev/approve-pending-deployments --pr <n>
```

If approval fails, those commands print **`ERROR: ENVIRONMENT_APPROVAL_FAILED`**. Stop and tell the operator — do not keep polling CI. The operator must approve the waiting environment or grant this `gh` identity reviewer access.

**`scripts/check-merge-settings`** is a thin wrapper (merge + GitHub MQ only). Prefer **`github-repo-lint`** for full coverage including branch cleanup workflows.

### `github-repo-lint` checks

Operator-oriented copy of this table also lives in [README.md](README.md#github-repo-lint-checks).

`scripts/lib/repo-practices` implements the audit. Use `--merge-only` (via `scripts/check-merge-settings`) to run only the merge-queue subset.

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
| Pre-PR checks cursor rule | yes* | — | `.cursor/rules/pre-pr-checks.mdc`: format before check + no truncated output; **consumer** repos must resolve `scripts/dev/` through the repository-helpers clone (`${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}`), not a bare repo-relative path (#579) (*missing FAILS `--new-repo` only; SUGGEST under org `--strict-onboarding` during roll-out; invalid FAILS `--new-repo` / `--strict-onboarding`) |
| Git commit identity cursor rule | yes | — | `.cursor/rules/git-commit-identity.mdc` forbids agent/machine co-authors; agents must verify commit signing (`commit.gpgsign` / `user.signingkey`, pinentry-mac / passphrase / per-machine keys / clearsign probe) and `~/.cursor/cli-config.json` attribution, and surface setup instructions when either is missing |
| No secret exposure cursor rule | yes* | — | `.cursor/rules/no-secret-exposure.mdc`: never leak secrets into logs/transcripts/PRs/commits; allowlist or path-existence when inspecting config; rotate if leaked (*missing FAILS `--new-repo` only; SUGGEST under org `--strict-onboarding` during roll-out; invalid FAILS `--new-repo` / `--strict-onboarding`) |
| Remote timeouts and retries cursor rule | yes* | — | `.cursor/rules/remote-timeouts-retries.mdc`: explicit timeouts on every remote call; bounded retries for transient failures only (`Retry-After` / cap / budget); anti-patterns for no-timeout calls and `while True` retries (*missing FAILS `--new-repo` only; SUGGEST under org `--strict-onboarding` during roll-out; invalid FAILS `--new-repo` / `--strict-onboarding`) |
| Repo practices after config change | yes | — | `.cursor/rules/repo-practices-after-config-change.mdc` requires `github-repo-lint` after workflow/config edits; `pre-pr-checks` runs detect-first `repo-practices-lint` when the diff touches those paths |
| Session-start read guidance | yes | — | `.cursor/rules/read-agents-and-rules.mdc` requires reading `AGENTS.md` and `.cursor/rules/` at the start of every new agent session |
| Agent bootstrap (agent-agnostic) | yes* | — | `AGENTS.md` at root + a session-startup line telling the agent to load `.cursor/rules/*.mdc`; `CLAUDE.md` (an `@AGENTS.md` import, or a symlink to `AGENTS.md`) and `.github/copilot-instructions.md` shims so Claude Code / Copilot reach the same guidance (templates in `scripts/lib/repo-practices-agents/`) (*missing shims / startup line SUGGEST under org `--strict-onboarding` during roll-out; FAIL `--new-repo`) |
| Secret-audit intake ledger | yes | — | Host-local `~/scratch/repository-helpers/secret-audit-intake.json` (not a git file; nightly-maintained): no entry FAILS `--new-repo` (SUGGEST under `--strict-onboarding` during roll-out); stale/invalid FAILS `--new-repo` / `--strict-onboarding`; ledger absent (CI runner) SUGGEST-only (TruffleHog deep scan — see [docs/secret-audit-trufflehog.md](./docs/secret-audit-trufflehog.md)) |
| Stacking-tool marker + rule | yes | — | `.github/stacking-tool` (`graphite`\|`gh-stack`) and thin `.cursor/rules/stacking-tool.mdc` (skill breadcrumbs; no copied skill bodies) |
| Stacking docs consistency | yes | — | When marker is `gh-stack`, fail if `pr-ship-and-review.mdc` still has Graphite-only `gt create`/`gt submit`, or if root `GRAPHITE.md` remains; suggest (non-failing) if `AGENTS.md` still prescribes Graphite/`gt`/`merge-it` without `gh stack`. Graphite marker gets a soft suggest if docs are gh-stack-only. Skips this repo (dual SSOT). Cutover checklist: `.cursor/rules/stacking-tool.mdc` |
| UV Python CVE check | yes | — | `uv.lock` + `pyproject.toml` repos require canonical `.github/workflows/cve-check.yml` |
| UV + Release Please lock sync | yes | — | uv + `release-please.yml` repos require `release-please-config` `extra-files` bumping `uv.lock` via `@.name.value` jsonpath ([release-please#2561](https://github.com/googleapis/release-please/issues/2561)) |
| Python static CI job | yes | — | Python (`pyproject.toml` + ruff) repos run ruff check/format + typecheck in one `Python lint & format checks` job via `.github/ci/python-static`; no split `Ruff`/`Pyright`/`Mypy`/`Backend Lint` jobs in **any** `.github/workflows/*`; cutover aliases must gate on `needs.python-static.result == 'success'` (or share conclusion via `aliases:` / `steps.*.outcome`) — see `.cursor/rules/python-static-ci-job.mdc` |
| `.cursor/rules` gitignore | yes | — | `.gitignore` must not block `.cursor/rules/` |
| Dependabot release age | yes | — | `cooldown` on every `dependabot.yml` updates entry (`release-age-defaults`) |
| pnpm release age | yes | — | `minimumReleaseAge` in `pnpm-workspace.yaml` when present |
| pnpm Corepack CI | yes | — | Exact `packageManager: pnpm@X.Y.Z` when lockfile exists; no `pnpm/action-setup` / `setup-node` `cache: pnpm`; use org composite `actions/setup-pnpm-corepack` (pin SHA on `main`; see section below) |
| `ci-secret-scan` gitleaks pin | yes* | — | Warn when `scripts/lib/ci-secret-scan` pins gitleaks behind the release-age-eligible version (*this repo only) |

`--suggest` prints remediation lines; `--apply-fix` queues candidate workflow/cursor-rule PRs via the stacking backend selected by `.github/stacking-tool` (`graphite` or `gh-stack`; org default `graphite` when the marker is missing) in the target repo clone.

See [`.cursor/skills/graphite/SKILL.md`](.cursor/skills/graphite/SKILL.md) for Graphite **stacking** (`gt`) when `.github/stacking-tool` is `graphite`. This repo trials **`gh-stack`** — see [`.cursor/skills/gh-stack/SKILL.md`](.cursor/skills/gh-stack/SKILL.md) and [`.cursor/rules/stacking-tool.mdc`](.cursor/rules/stacking-tool.mdc). Stacking is separate from merge enqueue (GitHub MQ).

### Stacking-tool marker cutover checklist

When flipping `.github/stacking-tool` (or landing an MQ / `gh-stack` cutover PR) in a
**consumer** repo, also:

1. Update `AGENTS.md` stacking and merge guidance to match the marker (GitHub auto-merge:
   `gh pr merge --auto --squash` — not `merge-it`).
2. Rewrite `.cursor/rules/pr-ship-and-review.mdc` submit block to the marker-aware template
   in `scripts/lib/repo-practices-cursor/pr-ship-and-review.mdc` (or document both backends
   gated on the marker — never leave a Graphite-only `gt create` / `gt submit` snippet when
   the marker is `gh-stack`).
3. Delete root `GRAPHITE.md` when switching to `gh-stack` (canonical skills live here).
4. Keep `.cursor/rules/stacking-tool.mdc` aligned with
   `scripts/lib/repo-practices-cursor/stacking-tool.mdc`.
5. Run `scripts/github-repo-lint --repo OWNER/NAME --suggest --strict-onboarding` and clear
   stacking-docs consistency findings (`--apply-fix` can rewrite pr-ship; AGENTS /
   `GRAPHITE.md` are usually human-driven).

### Lexicographic code organization (org Cursor rule)

Canonical rule: [`.cursor/rules/lexicographic-code-organization.mdc`](.cursor/rules/lexicographic-code-organization.mdc)
(public block then private `_` block; ASCII sort within each; sorted closed-set literals such as
`frozenset` / enum members).

Consumer repos should **copy** that file into their `.cursor/rules/` (or symlink it from a local
`repository-helpers` clone). Ensure `.gitignore` does not ignore `.cursor/rules/` (same policy as
other org cursor rules). Prefer `github-repo-lint --apply-fix` (uses
`scripts/lib/repo-practices-cursor/repo-practices-after-config-change.mdc`) or copy
that template into `.cursor/rules/`.

### `protect-main` ruleset (required)

Any repo with **GitHub merge queue** (`merge_queue` rule), **`release-please.yml`**, or **strict onboarding** must use the ruleset **`protect-main`** on `refs/heads/main`. Classic branch protection alone is **not** sufficient — the checker requires the ruleset. Org default enqueue is GitHub native merge queue (not Graphite MQ).

| Ruleset rule | Purpose |
| --- | --- |
| `deletion` | Block branch deletion |
| `non_fast_forward` | Block force-push |
| `pull_request` with `allowed_merge_methods: ["squash"]` | Squash-only merges (Release Please + merge queue) |
| `merge_queue` with `merge_method: SQUASH` | Native GitHub merge queue (org default); `check_response_timeout_minutes: 15` |

Graphite App bypass (`actor_id` **158384**) is **not** required for the org GitHub MQ profile. Leftover Graphite Integration bypass actors may be removed via `--apply-fix`.

Classic branch protection on **`main`** is also required (org standard). It complements the ruleset — reviews and CI — while **`protect-main`** enforces squash-only merges and GitHub `merge_queue`.

| Classic setting | GitHub MQ (org default) |
| --- | --- |
| Required reviews | CODEOWNERS, dismiss stale; **0** approvals |
| Bypass (reviews) | org owner (+ dependabot when present) |
| Push restrictions | **none** (GitHub MQ lands merges) |
| Required status checks | All `ci.yml` job contexts except `guard`, `changed-files`, `secret-scan`, `workflow-lint` |
| Strict | `true` |
| Force-push / delete | disabled |
| `enforce_admins` | `false` (warn if enabled) |

Create or repair ruleset + classic settings with
`scripts/github-repo-lint --repo OWNER/NAME --apply-fix`. Run it from the target
repository clone when you want candidate workflow fixes emitted as a stack
under `.worktrees/repo-practices-candidate-fixes-wt`.

### Org default: GitHub merge queue

**Org default** is **GitHub’s native merge queue** (not Graphite MQ):

- `protect-main` includes a `merge_queue` rule (`SQUASH`)
- `ci.yml` triggers on `merge_group` (and ignores `gh-readonly-queue/**` pushes when needed)
- Merge with **Enable auto-merge** / **Merge when ready** (or `gh pr merge --auto --squash`)
- Do **not** use the `merge-it` label to land PRs — leftover labels are harmless noise and are ignored by dep-updater

Disable org repos in [Graphite merge queue settings](https://app.graphite.com/settings/merge-queue) so Graphite does not also try to land PRs. Graphite **stacking** (`gt`, `.github/stacking-tool`) remains supported and is unrelated to merge enqueue.

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
- uses: actions/checkout@v7.0.1
- uses: actions/setup-node@v6.4.0
  with:
    node-version: '24'
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
- run: pnpm install --frozen-lockfile
```

Nested app (`packageManager` under `web/`):

```yaml
- uses: actions/checkout@v7.0.1
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

### Merge settings and GitHub merge queue

With no `--repo`, the script audits the **current git repository** when run inside a clone (from `origin`). Outside a clone, discovery includes repositories that have `release-please.yml`, GitHub `merge_queue`, or a leftover **`merge-it`** label (use `--all` to scan every org repo).

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

### GitHub merge queue

Org default is GitHub’s native merge queue. The checker validates `protect-main` `merge_queue` (`SQUASH`), `ci.yml` `merge_group`, and Dependabot auto-merge via `gh pr merge --auto` when `dependabot.yml` exists.

| Check | Org repos (GitHub MQ) |
| --- | --- |
| `protect-main` `merge_queue` (`SQUASH`) | required |
| Graphite App bypass on `protect-main` | not required (remove leftover bypass via `--apply-fix`) |
| `ci.yml` `merge_group` trigger | required |
| `dependabot-auto-merge.yml` with `gh pr merge --auto` when `dependabot.yml` exists | required (strict / onboarding) |
| Classic `main` protection (org standard) | required (no Graphite-only push restrictions) |
| Label `merge-it` / `merge-mq` | leftover only — harmless; do not use to land PRs |

**Manual:** disable org repos in [Graphite merge queue settings](https://app.graphite.com/settings/merge-queue) so Graphite does not also try to land PRs. Keep using Graphite (or `gh-stack`) for **stacking** only — selected by `.github/stacking-tool`.

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
- **Apply formatters before the gate** when planned jobs include format checks: `uv run ruff format .` / `cargo fmt --all`, then `scripts/dev/pre-pr-checks` (or `scripts/dev/pre-pr-checks --fix` / `PRE_PR_CHECKS_FORMAT=apply`). Commit format-only diffs before submit. Do **not** pipe pre-pr-checks to `tail`/`head`; require exit 0 and `==> pre-pr-checks passed`. `pytest` / `ruff check` alone is not a pre-PR pass.
- `pre-pr-checks` **detects the project type first** (filesystem markers only), then requires tools and runs **only planned jobs** in parallel:
  - **Shell**: helpers-style (`scripts/dev/pre-pr-checks`) → CI globs + `bash -n` / `shellcheck -S info`; or consumer `.github/ci/shellcheck` wrapper when present. Not every repo with a `scripts/` tree.
  - **Workflows**: `actionlint` when helpers-style or when workflows already invoke actionlint
  - **Bash tests**: `tests/*.test` when present (sequential, isolated TMPDIR)
  - **Python** (`pyproject.toml`): prefer `.github/ci/python-static`; else `uv run` ruff check/format + pyright
  - **Hermetic pytest**: when `.github/ci/pytest-hermetic` is present (same offline
    subset CI uses; not live Graph tests) — planned as `pytest-hermetic`
  - **TypeScript**: `web/package.json` → pnpm install + typecheck/build; else root pnpm (only when no `web/`) → `pnpm run check` (or typecheck/lint). Both layouts: web wins; root is not also planned.
  - **Rust** (`Cargo.toml`): `cargo fmt --all -- --check` and `cargo clippy --all-targets -- -D warnings`
  - **Secret scan**: when `.github/ci/secret-scan` or `scripts/dev/secret-scan` is
    present — runs canonical gitleaks (`scripts/lib/ci-secret-scan`) before submit
    (branch-vs-`main` range when possible). CI `secret-scan` remains post-push
    triage; this is the submit-path gate (see also deep/org scan #509 — TruffleHog via `scripts/secret-audit` / [docs/secret-audit-trufflehog.md](./docs/secret-audit-trufflehog.md)).
    Skip with `PRE_PR_CHECKS_SKIP=secret-scan`. Manual: `scripts/dev/secret-scan`.
  - **Verified commits**: when the branch has commits ahead of `main`/`origin/main` —
    `git verify-commit` locally, plus GitHub `verification.verified` when an upstream
    exists (bot authors skipped). Skip with `PRE_PR_CHECKS_SKIP=verified-commits`.
  - Escape hatch: `PRE_PR_CHECKS_SKIP=job1,job2` (documented; no silent skip). Do **not** bypass a failing run with ad-hoc substitutes.
  - Also verifies the **primary worktree** is unchanged when checks finish.
- Before submitting a PR, ensure it has a useful description (at minimum: **Summary** + **Test plan**).
- PRs must be **published (not draft)** so reviewers see them normally. Prefer `scripts/dev/submit-stack` for non-interactive submit (implies `--publish`).
- To merge a PR in **any org repo**: enable auto-merge / Merge when ready so GitHub’s merge queue lands it (`gh pr merge --auto --squash`). Do **not** use `merge-it` to enqueue. `dep-updater` batch runs (`--batch`, including daily `--batch --all`) use the same path after CI passes (`--merge-via gh` / `merge-queue` both mean `--auto --squash`; leftover `merge-it` is ignored).
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

**Copilot code review vs coding agent:** the review loop requests Copilot via
REST `requested_reviewers` with login `copilot-pull-request-reviewer` (same as
`gh pr edit --add-reviewer '@copilot'`).
Do **not** post `@copilot` issue comments or `--add-assignee '@copilot'` from the loop —
those engage **Copilot coding agent** (pushes commits / `copilot_work_*` timeline events),
not code review (`repository-helpers#461`).

**Copilot timeline failures:** credit exhaustion sometimes appears only as a PR timeline event
`copilot_work_finished_failure` (GitHub App `copilot-swe-agent`) with no issue comment or review
body. Quota observe scans that timeline event for the local calendar day. Non-quota work failures
of the same event type also mark Copilot exhausted for the day (acceptable for skip caches).
Outstanding `@copilot` / Bugbot `probe_requested` waits expire after
`AGENT_REVIEW_PROBE_REQUESTED_TTL` (default **15m**): the loop re-scans the current PR timeline
and advances the quota fallback chain instead of hanging (`repository-helpers#408`). Negative
`timeline_probed` cache entries are scoped to `OWNER/NAME#N` so another PR cannot skip the scan.

---

## Shell Script Conventions

- **No `.sh` extension.** Scripts live in `scripts/` and test harnesses in `tests/`. The shebang line declares the interpreter.
- **Nested runner sessions:** a child that sources `runner-bootstrap` must not keep the parent's `RUNNER_SESSION_DIR` (child EXIT would delete parent capture). See `.cursor/rules/runner-command-wrapper.mdc` (nested process sessions).
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
- Agents must follow `.cursor/rules/no-secret-exposure.mdc` (never print/paste secrets into logs, transcripts, PRs, or commits). Complements CI secret-scan: prevention vs detection.
- Agents must follow `.cursor/rules/remote-timeouts-retries.mdc` (explicit timeouts and bounded retries on every remote/network call).

---

## CI Checks (all must pass)

Run locally via **`scripts/dev/pre-pr-checks`** before every PR (detect-first ecosystem jobs + main worktree guard):

```
scripts/dev/pre-pr-checks            # preferred: planned jobs + main worktree guard
# bash-only subset when that is all that is detected:
bash -n … && shellcheck -S info … && actionlint … && bash tests/*.test
```

No PR may be merged with a failing CI check. No exceptions.
