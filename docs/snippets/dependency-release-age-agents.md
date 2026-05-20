## Dependency release age (10 days)

New dependency versions must be at least **10 days** old before this repo adopts them (see [repository-helpers](https://github.com/the-hcma/repository-helpers) `AGENTS.md`).

| Layer | Mechanism |
|-------|-----------|
| **pnpm** | `minimumReleaseAge: 14400` in `pnpm-workspace.yaml`. `minimumReleaseAgeExclude: ["*"]` grandfathers the **existing lockfile at cutover** so CI keeps working. |
| **Dependabot** | `cooldown: default-days: 10` on **version-update** PRs in `.github/dependabot.yml`. |
| **dep-updater** | Same 10-day npm gate when proposing bumps from repository-helpers. |

### CVE and security exceptions

- **Dependabot security updates** are not subject to the version-update cooldown.
- **dep-updater:** when `npm audit` reports CVE IDs with an available fix, dep-updater skips the 10-day npm gate for that package only.

**Day-to-day:** no grandfather scripts to run. Review Dependabot and dep-updater PRs as usual. Re-run `scripts/grandfather-pnpm-release-age` only if `pnpm-workspace.yaml` was lost after a major lockfile reset.
