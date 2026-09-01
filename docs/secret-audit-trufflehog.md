# TruffleHog deep secret audit (#509)

This document is the SSOT for how **TruffleHog** is used in this org: what it
locates, how `scripts/secret-audit` invokes it, the host-local intake ledger, and
how that differs from the fast **gitleaks** gate.

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

# Org wrapper (preferred — pinned release, --no-update). Scan only; no ledger write.
scripts/secret-audit --repo OWNER/NAME
scripts/secret-audit --all --org the-hcma --include-private

# Intake / stale refresh: after a clean scan, record intake in the host-local
# ledger (~/scratch/repository-helpers/secret-audit-intake.json). No git writes.
scripts/secret-audit --repo OWNER/NAME --write-marker
```

Override pin / install dir / parallelism:

- `TRUFFLEHOG_VERSION` (default pin in `scripts/lib/secret-audit`)
- `SECRET_AUDIT_BIN_DIR` (default `~/.cache/repository-helpers/bin`)
- `SECRET_AUDIT_CONCURRENCY` (optional positive integer → TruffleHog `--concurrency`;
  omit for TruffleHog’s default worker count — org mode already overlaps clone/scan)

Org sweeps always pass **`--exclude-archived`** so archived repositories are not
cloned. Plain `--all` is one fast `trufflehog github --org` sweep. `--all
--write-marker` instead scans each `rp_discover_org_repos` entry **individually**
(`git file://` for a local clone, `trufflehog github --repo` otherwise) and records
intake only for repos that scan clean — an aggregate `--org` exit of 0 cannot prove
every repo was actually reached.

## Intake ledger (host-local)

Path: **`~/scratch/repository-helpers/secret-audit-intake.json`**
(override with `SECRET_AUDIT_INTAKE_LEDGER`).

**Not a git file.** It is disposable operational state on the machine that runs the
`secret-audit` timer and the `github-repo-lint` enforcer — a sibling of
`secret-audit-batch.log` and `SECRET_AUDIT_DETAIL_DIR`. Lost or deleted, the next
nightly sweep rebuilds every entry; a fresh clean full-history scan is an
equal-or-stronger claim than what was lost, so there is nothing to back up
(repository-helpers#573).

```json
{ "_note": "...",
  "repos": {
    "the-hcma/<name>": { "status": "clean", "scanned_at": "<iso8601Z>",
      "scanner": "trufflehog", "scanner_version": "<semver>",
      "results_filter": "verified", "git_tip": "<sha>" } } }
```

| Field | Meaning |
| --- | --- |
| `status` | Always `clean` when present (an entry is written **only** after a clean scan) |
| `scanned_at` | ISO-8601 UTC when the deep scan finished — the freshness input |
| `scanner` / `scanner_version` | `trufflehog` + semver (audit trail; re-scan trigger after detector changes) |
| `results_filter` | e.g. `verified` — a `verified`-only clean is a weaker claim than `verified,unverified` |
| `git_tip` | Remote default-branch SHA at scan time — **informational only**, never compared for equality, omitted when unknown |

`repos` keys are ASCII-sorted for clean diffs.

Rules:

- An entry proves the **intake deep-history scan completed clean** — not a
  substitute for CI gitleaks or the nightly org sweep.
- **Maintained by the nightly sweep.** `secret-audit-batch-run` passes
  `--write-marker`, so the nightly run scans every discovered repo individually and
  upserts an entry for each one that scans clean. The 90-day staleness check
  therefore doubles as a "is the nightly sweep still running" canary.
- **`github-repo-lint` reads the ledger locally** — no Contents API, no default
  branch. The check is meaningful only where the ledger lives:

  | ledger state | routine `--all` | `--strict-onboarding` | `--new-repo` |
  | --- | --- | --- | --- |
  | file absent (CI runner, cold laptop) | skip | SUGGEST | SUGGEST |
  | no entry for the repo | SUGGEST | SUGGEST (roll-out) | **FAIL** `SECRET_AUDIT_INTAKE_MISSING` |
  | entry stale (>90d) or invalid | SUGGEST | **FAIL** | **FAIL** `SECRET_AUDIT_INTAKE_STALE` |
  | entry fresh + valid | OK | OK | OK |

  The CI `--all --strict-onboarding` audit does not check intake (no ledger on the
  runner) — acceptable: the hard gate is operator-run `--new-repo`, and the nightly
  sweep is the ongoing coverage.
- **On-demand:** `scripts/secret-audit --repo OWNER/NAME --write-marker` upserts one
  entry (scans first, records only on a clean result). No PR, no working-tree write.
- **Never** write `status=clean` when TruffleHog reports matching results.

A stray committed/untracked `.github/secret-audit.json` from the old per-repo scheme
is a leftover — delete it (`dev-worktree-guard` / `start-development` say so).

## Failure contract

| Line | Meaning |
| --- | --- |
| `ERROR: SECRET_AUDIT_LEAK …` | TruffleHog exit **183** (`--fail`) — rotate credentials; do not record intake |
| `ERROR: SECRET_AUDIT_INTAKE_MISSING …` | Lint `--new-repo`: repo has no ledger entry — run a clean deep scan |
| `ERROR: SECRET_AUDIT_INTAKE_STALE …` | Lint strict / new-repo: ledger entry invalid or >90 days old |
| `ERROR: SECRET_AUDIT_SCAN_FAILED …` | Tool / install / network / org-scan failure |
| `ERROR: SECRET_AUDIT_INFRA_FAILED …` | Batch exit non-zero with clean counters **and** no `ERROR: SECRET_AUDIT_SCAN_FAILED` in the transcript (teardown / runner infra; #540 / #541). A 0/0 counter line alone does not imply INFRA when the scan already failed. |

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
- Issue [#573](https://github.com/the-hcma/repository-helpers/issues/573) — host-local intake ledger (replaced the per-repo `.github/secret-audit.json` marker)
- Fast gate: `scripts/dev/secret-scan` / `.github/ci/secret-scan` (gitleaks)
- Lint check: `github-repo-lint` secret-audit intake ledger (AGENTS.md / README tables)
