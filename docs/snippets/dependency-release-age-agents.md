## Dependency release age (dep-updater 9 days, Dependabot 10 days)

New dependency versions are adopted on a staggered schedule so **dep-updater** (repository-helpers) lands updates before Dependabot (see [repository-helpers](https://github.com/the-hcma/repository-helpers) `AGENTS.md`).

| Layer | Mechanism |
|-------|-----------|
| **pnpm** | `minimumReleaseAge: 12960` (9 days) in `pnpm-workspace.yaml`. `minimumReleaseAgeExclude: ["*"]` grandfathers the **existing lockfile at cutover** so CI keeps working. |
| **dep-updater** | 9-day gate for npm, Python/PyPI, and GitHub Actions bumps (`scripts/lib/release-age-defaults`). |
| **Dependabot** | `cooldown: default-days: 10` on **version-update** PRs in `.github/dependabot.yml` (one day after dep-updater). |

### CVE and security exceptions

- **Dependabot security updates** are not subject to the version-update cooldown.
- **dep-updater:** when `npm audit` or `pip-audit` reports CVE IDs with an available fix, dep-updater skips the 9-day gate for that package only.

**Day-to-day:** no grandfather scripts to run. Review Dependabot and dep-updater PRs as usual. Re-run `scripts/grandfather-pnpm-release-age` only if `pnpm-workspace.yaml` was lost after a major lockfile reset.
