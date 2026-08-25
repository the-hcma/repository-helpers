# Systemd User Services

This repository ships systemd user services for daily repository maintenance:

| Service | Script | Timer | Report |
| --- | --- | --- | --- |
| `dep-updater.service` | `scripts/dep-updater-batch-run` | 03:00 daily | Dependency update run results |
| `github-repo-lint.service` | `scripts/github-repo-lint` | 04:00 daily | Repository-practices compliance |
| `secret-audit.service` | `scripts/secret-audit-batch-run` | 05:00 daily | TruffleHog org deep-scan results |

All three are oneshot services installed under `~/.config/systemd/user/`, with logs
under `~/scratch/repository-helpers/`.

### Timer oneshot conventions

Every timer-driven oneshot in this repository follows the same pattern:

1. **Timer-only activation** — the service unit has no `[Install]` section (no
   `default.target` pull-in). Only the `.timer` unit starts the job.
   `setup-service` enables the timer and disables any stale `default.target`
   service symlink from older installs.
2. **Singleton `flock`** — the entry script sources `scripts/lib/timer-singleton-lock`
   and calls `timer_singleton_acquire_lock` before doing work. Lock files live under
   `~/scratch/repository-helpers/` (one per service). A overlapping start exits 0
   and appends a skip line to the service log instead of sending email.

`ConditionPathExists` alone is not sufficient: it only gates scheduling and does
not atomically claim the lock when two starts race (`Persistent` catch-up plus
`OnCalendar`, or manual `systemctl start` during an active run). `flock` does.

| Service | Lock file |
| --- | --- |
| `dep-updater.service` | `~/scratch/repository-helpers/dep-updater-batch.lock` |
| `github-repo-lint.service` | `~/scratch/repository-helpers/github-repo-lint.lock` |
| `secret-audit.service` | `~/scratch/repository-helpers/secret-audit-batch.lock` |

New timer oneshots must use both conventions.

Unit **templates** (with `@@REPO_DIR@@`) live in each repository's `etc/systemd/`.
`setup-service` expands them into `~/.config/systemd/user/` and keeps a readable
copy under `~/.config/share/systemd-units/` for `scripts/show-services` (systemd
loads the install path, not the readable copy).
`setup-service` injects **`ConditionHost=|<machine-id>`** and **`ConditionHost=|<hostname>`** (both triggering) using the values in
`~/.config/user-services-machine-id` and `~/.config/user-services-host`
(and records FQDN in `user-services-host-fqdn` for status output) so units
run on one designated machine even when `~/.config/systemd/user/` is on NFS.
Re-run `setup-service` after changing the service host so installed units pick up
fresh guard lines.

### Service host (single-machine guard)

Units are pinned with **two** `ConditionHost=` lines after `[Unit]`:

| Line | Purpose |
| --- | --- |
| `ConditionHost=\|<machine-id>` | 32-char hex from `/etc/machine-id` on the service host (**systemd 259+**). |
| `ConditionHost=\|<short-hostname>` | Hostname OR-fallback — active guard on **older systemd**; also matches on 259+. |

```ini
# Service host: svc-host (svc-host.example; machine-id 7aeaef81…)
ConditionHost=|7aeaef81ca2647d09d2c2ef67e36bc84
ConditionHost=|svc-host
```

Both lines use the `|` (**triggering**) prefix, giving **OR** semantics: the unit
runs when the local machine-id matches (systemd 259+) **or** when the hostname
matches (all systemd versions). See
[systemd unit conditions](https://www.freedesktop.org/software/systemd/man/systemd.unit.html#Conditions%20and%20Asserts).

> **Why both triggering?** A non-triggering `ConditionHost=<hostname>` would be
> blocked on pre-259 systemd because `ConditionHost=|<machine-id>` (the only
> triggering condition) always fails there — a hostname string never equals a
> 32-char hex machine-id. Making the hostname condition triggering too restores OR
> semantics so units run correctly on the designated host at any systemd version.

| File | Purpose |
| --- | --- |
| `~/.config/user-services-host` | Short hostname label (e.g. `svc-host`) — prompts, status, and hostname `ConditionHost` |
| `~/.config/user-services-host-fqdn` | FQDN from `hostname -f` on the service host (e.g. `svc-host.example`) |
| `~/.config/user-services-machine-id` | 32-char hex ID from `/etc/machine-id` on the service host |

On the **first** `setup-service` run on the configured service host, the script
captures FQDN and `/etc/machine-id` into the files above. Other machines can
run `setup-service` to install or refresh units (e.g. over NFS), but scheduled
jobs must not run there.

`host_runs_units` (used by `setup-service`) is true when local `/etc/machine-id`
matches `~/.config/user-services-machine-id` **and** the hostname matches
`~/.config/user-services-host`. Timers enable on that host only; standbys skip
arming schedules via `timer_standby_disable` (stop-only; see below).

**systemd ≥ 259** is required for machine-id `ConditionHost` to be reliable in
units. On older systemd (hostname-only guard), the hostname `ConditionHost` line
is the active guard; upgrade systemd when possible so both guards apply.

`setup-service --status` reports whether this machine matches the configured
service host and notes when systemd is below 259.

**Standby hosts** (same NFS home, e.g. a laptop sharing `~`): `setup-service`
must **not** `systemctl --user disable` **timer** units for this repo (or delete
those timer unit files under `~/.config/systemd/user/`). Disable/remove on
standby removes shared `timers.target.wants/` symlinks and stops schedules on
the service host. `ConditionHost` already prevents those timers from firing on
standby. On standby, `timer_standby_disable` only stops the specific timer being
installed, and stale **timer** cleanup is skipped. Re-run `setup-service` on the
**configured service host** if wants links were ever removed and need re-enabling.

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
- **GitHub Repo Lint** is report-only. It monitors repository settings and
  workflow compliance, then tells you when to run `github-repo-lint --apply-fix` or
  disable Graphite’s merge-queue UI for org repos (GitHub MQ is the org default).

## Dependency Updater

The **Dependency Updater** runs `dep-updater --batch --all` over git repositories
discovered under a **scan root**. By default the scan root is the parent directory
of this checkout: `dep-updater` processes each immediate child directory that
contains a `.git` folder.

Batch runs default to **`--merge-via gh`**: after CI passes, each batch PR is
enqueued on GitHub’s merge queue with `gh pr merge --auto --squash`.
`DEP_UPDATER_MERGE_VIA=merge-queue` is an alias for the same enqueue path
(leftover `merge-it` labels are ignored).

Before each run, `scripts/dep-updater-batch-run` runs `git fetch --prune origin` on
this checkout and on each repository under the scan root so batch updates use the
latest remote refs.

### Timer (optional)

A daily schedule is **optional**. It is enabled when
`etc/systemd/dep-updater.timer` is present.
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
updates (dry-run). It loads the same `~/.config/dep-updater.env` for
`DEP_UPDATER_REPORT_TO` / `DEP_UPDATER_REPORT_FROM`. The timer batch job applies
updates and emails *run results* (success/failure per repo).

### Install

From this repository (any worktree):

```bash
./scripts/setup-service
```

This will:

1. Read templates from `etc/systemd/`, expand into `~/.config/systemd/user/`
2. Substitute `@@REPO_DIR@@` with the checkout you invoked setup from
3. Resolve the service-host short name from `~/.config/user-services-host` (or
   `--condition-host`), FQDN from `~/.config/user-services-host-fqdn` (captured
   on first run on the service host or `--condition-host-fqdn`), and machine-id
   in `~/.config/user-services-machine-id`
4. Inject `ConditionHost=|<machine-id>` into each unit
5. Enable lingering on the service host (when this machine's machine-id matches)
6. Run `scripts/on-deploy` to record the deployed commit
7. Enable the **timer** when `dep-updater.timer` exists (not an immediate batch run)

The service unit has **no `[Install]` section** — only `dep-updater.timer` starts it.
Re-run `./scripts/setup-service` after upgrading to drop a stale
`default.target.wants/dep-updater.service` symlink from older installs.

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

## GitHub Repo Lint (enforcer)

The **GitHub Repo Lint enforcer** scans GitHub clones under a root path and runs
`scripts/github-repo-lint --strict-onboarding --compact` across repositories in
the configured organization (default `the-hcma`; other owners are skipped). It
emails a daily report and exits non-zero when any repository fails the checks.

It reuses `~/.config/dep-updater.env` for SMTP. Add
`~/.config/github-repo-lint.env` only for enforcer-specific overrides,
such as the scan root or `GITHUB_REPO_LINT_ORG`:

```bash
cat >~/.config/github-repo-lint.env <<'EOF'
GITHUB_REPO_LINT_SCAN_ROOT=/path/to/repos
EOF
chmod 600 ~/.config/github-repo-lint.env
```

### Install

```bash
./scripts/setup-github-repo-lint
./scripts/setup-github-repo-lint --status
```

The wrapper uses `setup-service` with the `github-repo-lint` unit
template. It does not run from `scripts/dev/start-development`; installation is
explicit.

The service unit has **no `[Install]` section** — only `github-repo-lint.timer`
starts it (`OnCalendar=04:00`). Re-run `./scripts/setup-github-repo-lint` after
upgrading to drop a stale `default.target.wants/github-repo-lint.service` symlink
from older installs (that symlink caused a second run overlapping the timer).

See **Timer oneshot conventions** above for the shared `flock` rule and lock paths.

### Remediate findings

The enforcer reports drift. To apply supported GitHub-side repairs, run:

```bash
scripts/github-repo-lint --repo OWNER/NAME --apply-fix
```

`--apply-fix` can repair supported Release Please squash settings, `protect-main`
ruleset settings (squash-only + GitHub `merge_queue`), and classic `main` branch
protection. When run from the target repository clone, it also prepares candidate
workflow fixes in `.worktrees/repo-practices-candidate-fixes-wt` and submits a
stack for review. Candidate workflow templates live under
`scripts/lib/repo-practices-workflows/` so they can be reviewed and linted
directly. Disable org repos in Graphite’s merge-queue UI so Graphite does not
also try to land PRs.

### Status, logs, and trial runs

```bash
systemctl --user status github-repo-lint.service
systemctl --user list-timers github-repo-lint.timer
tail --follow=name --retry ~/scratch/repository-helpers/github-repo-lint.log

systemctl --user start github-repo-lint.service
```

### Uninstall

```bash
systemctl --user disable --now github-repo-lint.timer
systemctl --user disable github-repo-lint.service
rm ~/.config/systemd/user/github-repo-lint.{service,timer}
systemctl --user daemon-reload
```

## Secret audit (TruffleHog)

Daily **TruffleHog** org deep scan via `scripts/secret-audit-batch-run`. See
[secret-audit-trufflehog.md](./secret-audit-trufflehog.md) for detectors, result
filters, marker schema, and AGPL notes.

### Install

```bash
./scripts/setup-secret-audit
./scripts/setup-secret-audit --status
```

Optional `~/.config/secret-audit.env` overlays SMTP / org settings on top of
`~/.config/dep-updater.env`.

The service unit has **no `[Install]` section** — only `secret-audit.timer`
starts it (`OnCalendar=05:00`). Follow **Timer oneshot conventions** above for
the shared `flock` rule.

### Status and logs

```bash
systemctl --user status secret-audit.service
systemctl --user list-timers secret-audit.timer
tail --follow=name --retry ~/scratch/repository-helpers/secret-audit-batch.log
```
