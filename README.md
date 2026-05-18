# repository-helpers

General-purpose Bash scripts for managing repositories: service setup, development sessions, and dependency updates.

## Scripts

### `scripts/setup-service`

Installs a repository as a persistent **systemd user service**. Derives the service name from the repository directory — no hardcoding required.

```
Usage: scripts/setup-service [OPTIONS]

Options:
  (no options)   Install or update the systemd service
  --status       Check current service configuration and health
  --help         Show usage information
```

Reads a service unit template from `etc/systemd/<repo-name>.service` and expands `@@REPO_DIR@@` to the resolved repository path. Runs `scripts/on-deploy` (exit 0 = rebuilt, exit 1 = unchanged) if present, and restarts the service only when needed.

#### `scripts/on-deploy` contract

Repos with a systemd service should provide an executable `scripts/on-deploy` hook. `setup-service` calls it before (re)starting the unit:

| Exit code | Meaning |
|-----------|---------|
| `0` | Build or sync steps ran; the service must be restarted |
| `1` | Nothing changed; restart may be skipped |
| `2+` | Failure; `setup-service` aborts |

**Dependency expectations** (use `scripts/lib/on-deploy-deps` from this repo):

1. **Load the library** via `scripts/lib/on-deploy-deps-bootstrap` (copy the block from `docs/on-deploy-deps-load.snippet` into `on-deploy`; do not call library functions before `source`).
2. **Before skipping** on an unchanged commit, check staleness with `on_deploy_deps_python_env_stale` and, when the repo has a `package.json`, `on_deploy_deps_pnpm_modules_stale` (pass a subdir such as `web` for nested frontends).
3. **Bootstrap** a missing or broken `.venv` with `on_deploy_deps_bootstrap_python_venv` when the service uses uv.
4. **On a full deploy** (exit `0` path), run `on_deploy_deps_sync_python_frozen` and `on_deploy_deps_install_pnpm_frozen` before migrations, asset builds, or import smoke tests.

Commit-only skip caches must not ignore lockfile changes at the same SHA. See [AGENTS.md](AGENTS.md#on-deploy-hooks) for worktree and `.env` patterns.

---

### `scripts/dev/start-development`

Initializes a **development session**: prunes stale git worktrees, syncs Graphite, and either creates a new worktree or resumes an existing one.

```
Usage: scripts/dev/start-development [OPTIONS]

Options:
  --refresh   Pull latest main and ensure the service is running, then exit
  --resume    Prompt to resume an existing in-progress worktree
  --help      Show usage information
```

Requires `git`, `gh`, and `gt` (Graphite CLI) on `PATH`.

---

### `scripts/dep-updater`

Automates dependency version bumps across npm, pip, uv, and poetry ecosystems. Creates stacked Graphite PRs for each updated dependency.

See [dep-updater.plan.md](dep-updater.plan.md) for the full feature roadmap, and [dep-updater-hybrid-architecture.plan.md](dep-updater-hybrid-architecture.plan.md) for the Bash + Python extraction proposal.

---

### `scripts/dep-updater-notifier`

Companion to `dep-updater`. Posts a notification when dependency PRs are ready for review.

---

## Testing

Each script has a corresponding smoke test in `tests/`:

```bash
bash tests/setup-service.test
bash tests/start-development.test
bash tests/on-deploy-deps.test
bash tests/dep-updater.test
```

## Development

See [AGENTS.md](AGENTS.md) for coding conventions, linting rules, and CI requirements.  
See [GRAPHITE.md](GRAPHITE.md) for the branch stacking and PR workflow.
