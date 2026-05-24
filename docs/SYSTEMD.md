# Dependency Updater (systemd user service)

The **Dependency Updater** runs `dep-updater --batch --all` over git repositories
discovered under a **scan root**. By default the scan root is the parent directory
of this checkout: `dep-updater` processes each immediate child directory that
contains a `.git` folder.

Before each run, `scripts/dep-updater-batch-run` runs `git fetch --prune origin` on
this checkout and on each repository under the scan root so batch updates use the
latest remote refs.

## Timer (optional)

A daily schedule is **optional**. It is enabled only when the repo ships
`etc/systemd/dep-updater.timer` (same directory as the `.service` file).
`setup-service` installs and enables the timer when that file exists; if you remove
the timer template and re-run setup, the installed timer is disabled and removed.

Without a timer unit, only the oneshot service is installed — start it manually
when you want a batch run.

User **lingering** is enabled so scheduled (or manual) runs can execute without an
active login session.

## Prerequisites

- Linux with a systemd user session (`systemctl --user status` works)
- `gh`, `gt`, `jq`, `rg`, and ecosystem tools (`pnpm`, `uv`, …) on `PATH` or under
  `~/.local/bin` / NVM as for interactive runs
- `gh auth login` and `gt auth` completed for the service user
- Target repositories are git clones under the scan root (default:
  `$(dirname "$(git rev-parse --show-toplevel)")`)
- **`curl`** for SMTP email reports
- **`~/.config/repository-helpers/dep-updater.env`** (required; see below)

## Email reports (SMTP)

Each run executes `scripts/dep-updater-batch-run`, which:

1. Loads **`~/.config/repository-helpers/dep-updater.env`** (hard failure if missing)
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
mkdir -p ~/.config/repository-helpers
cp etc/dep-updater.env.example ~/.config/repository-helpers/dep-updater.env
chmod 600 ~/.config/repository-helpers/dep-updater.env
# Edit: DEP_UPDATER_SMTP_HOST, DEP_UPDATER_SMTP_USER, DEP_UPDATER_SMTP_PASSWORD,
#       DEP_UPDATER_REPORT_TO, DEP_UPDATER_REPORT_FROM
./scripts/setup-service   # reload unit after env changes
```

| Variable | Purpose |
| --- | --- |
| `DEP_UPDATER_SMTP_HOST` | SMTP server hostname |
| `DEP_UPDATER_SMTP_PORT` | Port (default `587`) |
| `DEP_UPDATER_SMTP_TLS` | `starttls` (default), `ssl`, or `plain` |
| `DEP_UPDATER_SMTP_USER` / `DEP_UPDATER_SMTP_PASSWORD` | AUTH (optional) |
| `DEP_UPDATER_REPORT_TO` | Where to send the report |
| `DEP_UPDATER_REPORT_FROM` | Envelope / From address |
| `DEP_UPDATER_BATCH_TIMEOUT` | Batch deadline (`4h`, `240m`, or seconds; default `4h`) |

Preview a report email without running the batch (uses the same env file):

```bash
./scripts/dep-updater-batch-run --print
```

**Separate tool:** `scripts/dep-updater-notifier` emails when scans find *available*
updates (dry-run). The timer batch job applies updates and emails *run results*
(success/failure per repo).

## Install

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

## Status and logs

```bash
./scripts/setup-service --status
systemctl --user status dep-updater.service
systemctl --user list-timers dep-updater.timer   # when timer is installed
journalctl --user -u dep-updater.service -n 100
tail -f ~/scratch/repository-helpers/dep-updater-batch.log
```

## Run batch manually

```bash
systemctl --user start dep-updater.service
```

## Change schedule or scan root

Edit `etc/systemd/dep-updater.timer` (calendar) or set
`DEP_UPDATER_BATCH_SCAN_ROOT` in `~/.config/repository-helpers/dep-updater.env` or a
unit override, then re-run `./scripts/setup-service`.

## Uninstall

```bash
systemctl --user disable --now dep-updater.timer   # if installed
systemctl --user disable dep-updater.service
rm ~/.config/systemd/user/dep-updater.{service,timer}
systemctl --user daemon-reload
```
