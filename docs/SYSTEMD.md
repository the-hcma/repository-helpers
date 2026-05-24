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
`DEP_UPDATER_BATCH_SCAN_ROOT` in the environment / unit override, then re-run
`./scripts/setup-service`.

## Uninstall

```bash
systemctl --user disable --now dep-updater.timer   # if installed
systemctl --user disable dep-updater.service
rm ~/.config/systemd/user/dep-updater.{service,timer}
systemctl --user daemon-reload
```
