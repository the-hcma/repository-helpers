# TruffleHog deep secret audit (#509)

This document is the SSOT for how **TruffleHog** is used in this org: what it
locates, how `scripts/secret-audit` invokes it, the intake marker schema, and how
that differs from the fast **gitleaks** gate.

## Why two scanners?

| Layer | Engine | Scope | When |
| --- | --- | --- | --- |
| PR / pre-submit | **gitleaks** (`scripts/lib/ci-secret-scan`) | Recent diff or working tree | Every PR; `pre-pr-checks` / `scripts/dev/secret-scan` when adopted |
| Intake + periodic | **TruffleHog** (`scripts/secret-audit`) | **Full git history** (+ live verification) | Repo onboarding; scheduled org sweeps |

**gitleaks** is fast and diff-oriented — ideal before merge. It does not walk
entire history on every run.

**TruffleHog** is the slow, thorough pass. Secrets may already live in historical
commits or on branches that never hit PR CI. New or imported repos can carry
leaks before any gitleaks job runs. TruffleHog closes that gap.

TruffleHog does **not** replace gitleaks in CI or pre-pr-checks. Keep both.

## What TruffleHog locates

TruffleHog ships **800+ detectors** for credential-like material, including (non-
exhaustive):

| Category | Examples |
| --- | --- |
| Cloud / IaaS | AWS access keys, GCP service-account JSON, Azure tokens |
| Source control | GitHub PATs / App tokens, GitLab tokens |
| SaaS / payments | Slack tokens, Stripe secret keys, Twilio, SendGrid |
| Data stores | Postgres / MySQL connection strings, MongoDB URIs |
| Crypto / TLS | PEM private keys, SSH keys (with live verification via Driftwood where applicable) |
| Generic high-entropy | Many detector-specific API key formats |

Upstream detector list (do not mirror in-tree):  
https://github.com/trufflesecurity/trufflehog (see `pkg/detectors`).

### Result classes

| Class | Meaning |
| --- | --- |
| `verified` | Live API / crypto check says the credential still works |
| `unverified` | Pattern matched; not confirmed live |
| `unknown` | Verification errored (network / API / rate limit) |

**Org automation default:** `--results=verified` so reports prioritize actionable,
still-valid credentials. Operators may widen to `verified,unknown` or
`verified,unknown,unverified` for triage; that is not the timer default.

### Where we scan (v1)

| Mode | Command shape | Use |
| --- | --- | --- |
| Local full history | `trufflehog --no-update git file://$REPO --results=verified --fail` | Intake / local clone (preferred when a full clone exists) |
| Single remote repo | `GITHUB_TOKEN=… trufflehog --no-update github --repo=OWNER/NAME --results=verified --fail` | When no local clone is available (prefer `scripts/secret-audit`; token via env, never argv) |
| Org sweep | `GITHUB_TOKEN=… trufflehog --no-update github --org=ORG --exclude-archived --results=verified --fail` | Periodic timer / `--all` (wrapper sets env + `--fail`; optional `--concurrency` via `SECRET_AUDIT_CONCURRENCY`) |

**Not used for intake in v1:**

- `trufflehog filesystem …` — tip/working-tree only; misses packfile / history
  objects (see TruffleHog’s git-vs-filesystem guidance).
- S3, Docker, GCS, chat, CI-log sources — out of scope for this wrapper.

Always pass **`--no-update`** in automation (Homebrew Cellar and pinned installs are
not writable by the in-binary updater). Upgrade with `brew upgrade trufflehog` or
by bumping `secret_audit_trufflehog_version` / `TRUFFLEHOG_VERSION` **and** the
matching in-repo SHA-256 pins in `secret_audit_trufflehog_pinned_sha256` (release
`checksums.txt` is not trusted — same mutable host as the tarball).

Checksum verification uses GNU `sha256sum` (Homebrew `coreutils` gnubin on Darwin
via `tooling_path_ensure_gnu_userland`).

Shallow clones only see shallow history — the wrapper runs `git fetch --unshallow`
when needed before a `git file://` deep scan.

## Operator commands

```bash
# Install (Homebrew) or let the wrapper download the pinned release
brew install trufflehog
# Homebrew: always pass --no-update
trufflehog --no-update git file://. --results=verified --fail

# Org wrapper (preferred — pinned release, --no-update). Scan only; no marker write.
scripts/secret-audit --repo OWNER/NAME
scripts/secret-audit --all --org the-hcma --include-private

# Intake / stale-marker refresh: writes .github/secret-audit.json into the clone.
# Commit and push the result — lint reads the marker from the default branch.
scripts/secret-audit --repo OWNER/NAME --write-marker
```

Override pin / install dir / parallelism:

- `TRUFFLEHOG_VERSION` (default pin in `scripts/lib/secret-audit`)
- `SECRET_AUDIT_BIN_DIR` (default `~/.cache/repository-helpers/bin`)
- `SECRET_AUDIT_CONCURRENCY` (optional positive integer → TruffleHog `--concurrency`;
  omit for TruffleHog’s default worker count — org mode already overlaps clone/scan)

Org sweeps always pass **`--exclude-archived`** so archived repositories are not
cloned. Marker refresh after a clean org scan uses the same archived filter via
`rp_exclude_archived` on `rp_discover_org_repos` (local clones of archived repos
are skipped).

## Marker file

Path: **`.github/secret-audit.json`**

Written **only** after a clean scan (no matching `--results`). Never commit finding
payloads or raw secrets into the marker.

| Field | Meaning |
| --- | --- |
| `status` | Always `clean` when present (never write on leaks) |
| `scanned_at` | ISO-8601 UTC when the deep scan finished |
| `scanner` | `trufflehog` |
| `scanner_version` | TruffleHog semver |
| `git_tip` | Default-branch / HEAD SHA that was scanned |
| `results_filter` | e.g. `verified` |
| `tool` | `repository-helpers/secret-audit` |

Rules:

- Marker proves **intake (and later refresh) completed successfully** — not a
  substitute for CI gitleaks.
- `github-repo-lint` FAILS under `--new-repo` when the marker is missing
  (intake gate). Under `--strict-onboarding` / `--new-repo` it FAILS when the
  marker is unparseable or stale (>90 days). Missing markers under org
  `--strict-onboarding --all` only SUGGEST (v1 roll-out grandfather until
  operators write markers). Routine audits SUGGEST remediation.
- The marker is an **intake artifact written by an operator**, not a nightly
  heartbeat. Lint reads it from the **remote default branch** (Contents API), so a
  marker is only meaningful once it is committed and pushed.
- The **host timer does not write markers** (`secret-audit-batch-run` omits
  `--write-marker`). A local write never reaches the Contents API that lint reads,
  and it leaves the primary clone dirty, which trips the `pre-pr-checks`
  main-worktree guard on the next PR (repository-helpers#534). The nightly email
  still reports scan outcome.
- Refresh a marker by hand when `github-repo-lint` reports it stale
  (>`secret_audit_marker_stale_days`): run `--write-marker` against a clone, then
  land the change on the **default branch** (push directly, or merge a PR) so lint
  sees the new `scanned_at`. An unmerged PR does not update the branch lint reads.
- **Never** write or refresh `status=clean` when TruffleHog reports matching results.

`--write-marker` requires a **local clone** (scan root or cwd). When an operator pairs
it with `--all`, markers refresh only for clones that already exist locally. A verified
leak found during that local refresh fails the run with exit **183**; a single clone
whose origin fetch fails is skipped with WARN so the rest of the sweep can continue.
The host timer never takes this path.

## Failure contract

| Line | Meaning |
| --- | --- |
| `ERROR: SECRET_AUDIT_LEAK …` | TruffleHog exit **183** (`--fail`) — rotate credentials; do not refresh marker |
| `ERROR: SECRET_AUDIT_MARKER_MISSING …` | Lint: no valid marker on default branch (strict / new-repo) |
| `ERROR: SECRET_AUDIT_SCAN_FAILED …` | Tool / install / network / org-scan failure |
| `ERROR: SECRET_AUDIT_INFRA_FAILED …` | Batch exit non-zero while TruffleHog counters are clean (teardown / runner infra; repository-helpers#540 / #541) |

Remediation: revoke and rotate, remove secrets from the tree, re-scan. History
rewrite requires explicit human ownership — the wrapper never auto-purges git
history.

## Periodic timer

| Unit | Entry | Schedule |
| --- | --- | --- |
| `secret-audit.service` | `scripts/secret-audit-batch-run` | via `secret-audit.timer` (05:00) |

Install:

```bash
scripts/setup-secret-audit
scripts/setup-secret-audit --status
```

Reuses `~/.config/dep-updater.env` for SMTP; optional overlay
`~/.config/secret-audit.env` (see `etc/secret-audit.env.example`) for
`SECRET_AUDIT_REPORT_TO` / From, org flags, `SECRET_AUDIT_CONCURRENCY`, and detail
paths. Follows timer oneshot conventions (`docs/SYSTEMD.md`): timer-only activation
+ flock.

**Email privacy:** the batch report is summary-only — PASS/FAIL, org, exit/result,
optional `Primary:` / `Command failures` from the runner session (labels, exit codes,
tool stderr hints only), repos in scope (names from the org API), passed/failed counts,
TruffleHog finding *counts* (verified/unverified secret matches — not “repos vetted”),
scan duration (rounded to two decimals for display), and the path to the host transcript.
Wall-clock Started/Finished appear once in the
run-context footer. Finding payloads are **never** emailed — full output is deposited
under `SECRET_AUDIT_DETAIL_DIR` (default `~/scratch/repository-helpers/secret-audit-runs/`,
mode `0600`) and also appended to the batch log. See repository-helpers#559.

## AGPL note

TruffleHog is **[AGPL-3.0](https://github.com/trufflesecurity/trufflehog)**.
repository-helpers **invokes** the released binary as an external process — it does
not vendor or link TruffleHog source. Operators who modify TruffleHog itself must
comply with AGPL distribution terms; merely running the official release from org
automation does not trigger copyleft on this Bash repo.

## Related

- Issue [#509](https://github.com/the-hcma/repository-helpers/issues/509)
- Issue [#516](https://github.com/the-hcma/repository-helpers/issues/516) — exclude archived; concurrency; summary email
- Issue [#559](https://github.com/the-hcma/repository-helpers/issues/559) — clearer batch email (repo list, findings vs pass/fail)
- Fast gate: `scripts/dev/secret-scan` / `.github/ci/secret-scan` (gitleaks)
- Lint check: `github-repo-lint` secret-audit intake marker (AGENTS.md / README tables)
