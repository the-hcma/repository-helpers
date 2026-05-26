# Systemd User Services

This repository ships systemd user services for daily repository maintenance:

| Service | Script | Timer | Report |
| --- | --- | --- | --- |
| `dep-updater.service` | `scripts/dep-updater-batch-run` | 03:00 daily | Dependency update run results |
| `repo-big-brother-enforcer.service` | `scripts/repo-big-brother-enforcer` | 04:00 daily | Repository-practices compliance |

Both are oneshot services installed under `~/.config/systemd/user/`, with logs
under `~/scratch/repository-helpers/`.

Use `scripts/show-services` for a read-only overview of every service template in
this repo:

```bash
scripts/show-services
```

The summary includes installed/up-to-date state, active/enabled state, timer state
and next run, `ExecStart`, working directory, user configuration files, log tail
commands, and the setup command for each service.

The services have different responsibilities:

- **Dependency Updater** is allowed to create and update dependency PRs. Its email
  reports summarize what changed, what failed, and whether the run timed out.
- **Repo Big Brother Enforcer** is report-only. It monitors repository settings and
  workflow compliance, then tells you when to run `check-repo-practices --apply-fix` or
  complete manual Graphite app steps.

## Dependency Updater

The **Dependency Updater** runs `dep-updater --batch --all` over git repositories
discovered under a **scan root**. By default the scan root is the parent directory
of this checkout: `dep-updater` processes each immediate child directory that
contains a `.git` folder.

Before each run, `scripts/dep-updater-batch-run` runs `git fetch --prune origin` on
this checkout and on each repository under the scan root so batch updates use the
latest remote refs.

### Timer (optional)

A daily schedule is **optional**. It is enabled only when the repo ships
`etc/systemd/dep-updater.timer` (same directory as the `.service` file).
`setup-service` installs and enables the timer when that file exists; if you remove
the timer template and re-run setup, the installed timer is disabled and removed.

Without a timer unit, only the oneshot service is installed — start it manually
when you want a batch run.

User **lingering** is enabled so scheduled (or manual) runs can execute without an
active login session.

### Prerequisites

- Linux with a systemd user session (`systemctl --user status` works)
- `gh`, `gt`, `jq`, `rg`, and ecosystem tools (`pnpm`, `uv`, …) on `PATH` or under
  `~/.local/bin` / NVM as for interactive runs
- `gh auth login` and `gt auth` completed for the service user
- Target repositories are git clones under the scan root (default:
  `$(dirname "$(git rev-parse --show-toplevel)")`)
- **`curl`** for SMTP email reports
- **`~/.config/dep-updater.env`** (required; see below)

### Email reports (SMTP)

Each run executes `scripts/dep-updater-batch-run`, which:

1. Loads **`~/.config/dep-updater.env`** (hard failure if missing)
2. Runs `git fetch --prune origin` on this checkout and each repository under the scan root
3. Runs `dep-updater --batch --all` under a **deadline** (`DEP_UPDATER_BATCH_TIMEOUT`,
   default **4h**). When the limit is exceeded, `timeout(1)` stops the batch (and child
   processes), logs `ERROR: WAIT_TIMEOUT batch-run …`, and emails a timeout failure report.
4. Appends output to `~/scratch/repository-helpers/dep-updater-batch.log`
5. Sends a notifier-style email summary (plain + HTML `pre`) via SMTP

The installed unit sets `TimeoutStartSec=4h 30min` and `KillMode=control-group` as a
systemd safety net (slightly above the default script deadline). If you raise
`DEP_UPDATER_BATCH_TIMEOUT`, increase `TimeoutStartSec` in a drop-in or edit the template
and re-run `./scripts/setup-service`.

The env file is **mandatory**: the systemd unit uses `EnvironmentFile=` without the
optional `-` prefix, and the script exits with an error if the file is absent or
incomplete.

Configure reporting:

```bash
cp etc/dep-updater.env.example ~/.config/dep-updater.env
chmod 600 ~/.config/dep-updater.env
# For local sendmail, only DEP_UPDATER_SMTP_HOST=localhost is required.
./scripts/setup-service   # reload unit after env changes
```

| Variable | Purpose |
| --- | --- |
| `DEP_UPDATER_SMTP_HOST` | Mail host (`localhost` uses local **sendmail**; only required setting) |
| `DEP_UPDATER_REPORT_TO` | Report recipient (default `johndoe@example.com`) |
| `DEP_UPDATER_REPORT_FROM` | Sender address (default `dep-updater-batch@example.com`) |
| `DEP_UPDATER_SMTP_PORT` | Remote SMTP port (default `587`; `25` for localhost) |
| `DEP_UPDATER_SMTP_TLS` | `starttls` (default), `ssl`, or `plain` |
| `DEP_UPDATER_SMTP_USER` / `DEP_UPDATER_SMTP_PASSWORD` | Remote SMTP AUTH (optional) |
| `DEP_UPDATER_BATCH_TIMEOUT` | Batch deadline (`4h`, `240m`, or seconds; default `4h`) |

Preview a report email without running the batch (uses the same env file):

```bash
./scripts/dep-updater-batch-run --print
```

**Separate tool:** `scripts/dep-updater-notifier` emails when scans find *available*
updates (dry-run). The timer batch job applies updates and emails *run results*
(success/failure per repo).

### Install

From this repository (any worktree):

```bash
./scripts/setup-service
```

This will:

1. Install `etc/systemd/dep-updater.service` (and `.timer` when present)
   under `~/.config/systemd/user/`
2. Substitute `@@REPO_DIR@@` with the checkout you invoked setup from
3. Enable lingering for your user
4. Run `scripts/on-deploy` to record the deployed commit
5. Enable the **timer** when `dep-updater.timer` exists (not an immediate batch run)

### Status and logs

```bash
./scripts/setup-service --status
systemctl --user status dep-updater.service
systemctl --user list-timers dep-updater.timer   # when timer is installed
journalctl --user -u dep-updater.service -n 100
tail -f ~/scratch/repository-helpers/dep-updater-batch.log
```

### Run batch manually

```bash
systemctl --user start dep-updater.service
```

### Change schedule or scan root

Edit `etc/systemd/dep-updater.timer` (calendar) or set
`DEP_UPDATER_BATCH_SCAN_ROOT` in `~/.config/dep-updater.env` or a
unit override, then re-run `./scripts/setup-service`.

### Uninstall

```bash
systemctl --user disable --now dep-updater.timer   # if installed
systemctl --user disable dep-updater.service
rm ~/.config/systemd/user/dep-updater.{service,timer}
systemctl --user daemon-reload
```

## Repo Big Brother Enforcer

The **Repo Big Brother Enforcer** scans GitHub clones under a root path and runs
`scripts/check-repo-practices --strict-onboarding --compact` across the discovered
repositories. It emails a daily report and exits non-zero when any repository fails
the checks.

It reuses `~/.config/dep-updater.env` for SMTP. Add
`~/.config/repo-big-brother-enforcer.env` only for enforcer-specific overrides,
such as the scan root:

```bash
cat >~/.config/repo-big-brother-enforcer.env <<'EOF'
REPO_BIG_BROTHER_SCAN_ROOT=/path/to/repos
EOF
chmod 600 ~/.config/repo-big-brother-enforcer.env
```

### Install

```bash
./scripts/setup-repo-big-brother-enforcer
./scripts/setup-repo-big-brother-enforcer --status
```

The wrapper uses `setup-service` with the `repo-big-brother-enforcer` unit
template. It does not run from `scripts/dev/start-development`; installation is
explicit.

### Remediate findings

The enforcer reports drift. To apply supported GitHub-side repairs, run:

```bash
scripts/check-repo-practices --repo OWNER/NAME --apply-fix
```

`--apply-fix` can repair supported Release Please squash settings, `protect-main`
ruleset settings, and classic `main` branch protection. Graphite app merge queue
configuration remains manual and is reported as a manual step in the output.

### Status, logs, and trial runs

```bash
systemctl --user status repo-big-brother-enforcer.service
systemctl --user list-timers repo-big-brother-enforcer.timer
tail --follow=name --retry ~/scratch/repository-helpers/repo-big-brother-enforcer.log

systemctl --user start repo-big-brother-enforcer.service
```

### Uninstall

```bash
systemctl --user disable --now repo-big-brother-enforcer.timer
systemctl --user disable repo-big-brother-enforcer.service
rm ~/.config/systemd/user/repo-big-brother-enforcer.{service,timer}
systemctl --user daemon-reload
```
