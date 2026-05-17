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
bash tests/dep-updater.test
```

## Development

See [AGENTS.md](AGENTS.md) for coding conventions, linting rules, and CI requirements.  
See [GRAPHITE.md](GRAPHITE.md) for the branch stacking and PR workflow.
