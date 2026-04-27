# AGENTS.md — Ground Rules for dep-updater

This file defines the non-negotiable standards for all contributors (human or AI) working on this codebase. Every change must comply with these rules before it is considered complete.

---

## Language & Runtime

- Scripts live in `scripts/` (e.g. `scripts/dep-updater`, `scripts/setup-service`). Sub-directories are allowed (e.g. `scripts/dev/start-development`).
- Tests live in `tests/` and mirror the script name (e.g. `tests/dep-updater.test`).
- Target **bash ≥ 5.x** (every script declares `#!/usr/bin/env bash` and uses `set -euo pipefail`).
- External runtime dependencies: `git`, `gt` (Graphite CLI), `gh` (GitHub CLI), `jq`, `rg` (ripgrep), plus the ecosystem tools being managed (`pnpm`, `pip`, `uv`, `poetry`) as optional callees.
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
- Test names must read as sentences: `output contains "[worktree] Creating worktree at:"`.
- Do not write tests that only assert a function was reached — assert the observable output or exit code.

---

## Repository

- Remote: `https://github.com/the-hcma/repository-helpers` (private).
- Do not make the repository public without explicit approval.
- Never commit secrets, credentials, or API keys — use environment variables.

---

## dep-updater Behavioral Invariants

- **Never introduce `==` pins.** dep-updater always writes `>=` floor constraints when bumping a dependency. It must never lock a package to an exact version.
- **Respect existing pins for pip / pipenv / poetry.** For these ecosystems, `==` signals a deliberate user decision to lock a specific version. dep-updater skips those packages entirely (`py_is_pinned`).
- **uv `==` pins are not treated as intentional freezes.** dep-updater updates them and promotes the constraint to `>=` on bump. The transitive constraint check (`uv pip install --dry-run`) still gates upgrades that would violate real transitive constraints.

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

Use `--refresh` to pull the latest `main` and ensure the service is running without opening a new worktree:

```bash
scripts/dev/start-development --refresh
```

## Worktree-aware Scripts

`setup-service` and `scripts/on-deploy` are **worktree-aware**: all paths (service template at `etc/systemd/`, `@@REPO_DIR@@` substitution in the generated unit file, and the `on-deploy` hook itself) are resolved from whichever worktree the script is invoked from. Calling `setup-service` from a feature worktree therefore deploys that worktree's code — this is intentional and is the primary mechanism for testing feature branches locally.

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

---

## Commits, Stacking & Pull Requests

> See [GRAPHITE.md](./GRAPHITE.md) for the full Graphite workflow reference (branch naming, stack creation, navigation, submission, troubleshooting, and advanced rebasing).

- This project uses **Graphite** (`gt`) for branch stacking.
- All work is done in stacked branches via `gt create`, `gt modify`, and `gt submit`.
- Never work directly on `main`. Always create a stack branch: `gt create -m "feat: description"`.
- Keep each branch in the stack focused on exactly one logical change. Stacks should map 1-to-1 with milestones or sub-tasks from [dep-updater.plan.md](./dep-updater.plan.md).
- Sync regularly: `gt sync` before starting new work; `gt restack` after upstream changes land.
- Submit stacks with `gt submit` — do not open PRs manually via the GitHub UI.
- To merge a PR, add the `merge-it` label: `gh pr edit <number> --add-label merge-it`. Never use `gh pr merge` directly.
- Follow **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
- Each commit must pass all CI checks (see below) before being pushed.
- Keep commits focused. One logical change per commit.
- PR descriptions must reference the relevant milestone from [dep-updater.plan.md](./dep-updater.plan.md).
- Before starting a new PR or branch, confirm the current PR is either merged or that all CI checks pass. Never start new work on a broken base.

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
- **Never declare `local -r` or plain `local` inside a loop body.** Hoist all `local` declarations to the top of the function. `local -r` inside a loop will crash on the second iteration with "readonly variable" because `local -r` both declares and sets, and re-entering the loop tries to re-declare an already-readonly name.
- Do not use `A && B || C` as an if-then-else substitute (SC2015). Use a proper `if/then/else` block.
- **Prefer long-form flags** for all command invocations (e.g. `--follow=name` not `-f`, `--all` not `-a`). Short flags are allowed only when no long form exists.

---

## Security

- All file paths received from the CLI must be validated and resolved with `realpath`/`readlink -f` before any file system operation. Reject paths that escape the working directory.
- No dynamic `eval` or command construction from user-controlled strings.
- Do not log, store, or transmit credential tokens beyond what is needed to invoke `gh`/`gt`.

---

## CI Checks (all must pass)

```
bash -n scripts/* tests/*            # syntax check (add new files here)
shellcheck -S info scripts/* tests/* # lint (add new files here)
bash tests/<script-name>.test        # run individual test suite
```

No PR may be merged with a failing CI check. No exceptions.
