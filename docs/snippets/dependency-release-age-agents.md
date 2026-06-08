## Dependency release age (dep-updater 9 days, Dependabot 10 days)

New dependency versions are adopted on a staggered schedule so **dep-updater** (repository-helpers) lands updates before Dependabot (see [repository-helpers](https://github.com/the-hcma/repository-helpers) `AGENTS.md`).

| Layer | Mechanism |
|-------|-----------|
| **pnpm** | `minimumReleaseAge: 12960` (9 days) in `pnpm-workspace.yaml`. `minimumReleaseAgeExclude: ["*"]` grandfathers the **existing lockfile at cutover** so CI keeps working. |
| **dep-updater** | 9-day gate for npm, Python/PyPI, and GitHub Actions bumps (`scripts/lib/release-age-defaults`). |
| **Dependabot** | Weekly scan + `cooldown: default-days: 10` on **version-update** PRs in `.github/dependabot.yml` (one day after dep-updater). Do **not** set `open-pull-requests-limit: 0` — version updates stay enabled as a backup. |

### Dependabot: version bumps vs security

- **Version updates** — Dependabot checks on the weekly schedule; each proposed bump must pass the **10-day cooldown** (release age). dep-updater usually lands the same bump first (9-day gate); Dependabot version PRs after that are redundant and can be closed.
- **Security updates** — **not** subject to the version-update cooldown. Dependabot may open a security PR as soon as GitHub has an alert and a fix; merge these promptly.
- **dep-updater CVE bypass** — when `npm audit` or `pip-audit` reports CVE IDs with an available fix, dep-updater skips the 9-day gate for that package only (`--security-only` mode is available).

**Day-to-day:** merge dep-updater batch PRs for routine bumps; close duplicate Dependabot version PRs when dep-updater already has the change. Re-run `scripts/grandfather-pnpm-release-age` only if `pnpm-workspace.yaml` was lost after a major lockfile reset.
