---
description: Discover org repo names programmatically; never hardcode sibling repos
alwaysApply: true
---

# No hardcoded org repo names

Generic org tooling (`scripts/lib/repo-practices`, `scripts/github-repo-lint`,
`scripts/check-merge-settings`, and other shared `scripts/lib/*` helpers) must
**not** embed sibling repository names or `OWNER/NAME` slugs as string literals.

Default org is **`the-hcma`** (`rp_DEFAULT_ORG`). Discover repos at runtime.

## Do

- Iterate org repos with `rp_discover_org_repos`, `rp_discover_audit_repos`, or
  `gh api "orgs/${org}/repos"` / `gh repo list the-hcma`.
- Resolve the current clone with `rp_resolve_local_repo_dir` / `git remote`.
- Refer to **this** repo only via `rp_THIS_REPO_NAME` / `${rp_DEFAULT_ORG}/${rp_THIS_REPO_NAME}` — never bare `repository-helpers` in suggest text.
- Gate repo-specific behavior on **discovered** slug variables
  (`rp_repo_short_name "$slug"`, `[[ "$repo_name" == … ]]`) after discovery — not inline literals in shared libs.
- In tests, enforce with `rp_assert_no_hardcoded_consumer_repo_names` from
  `tests/lib/test-assert` (reads org/this-repo constants from the lib under test).

## Do not

- Hardcode consumer names in suggest/fail messages (`see fpdf`, `from domesti-bot`, etc.).
- Use `grep -qF 'some-sibling-repo'` in static tests as a stand-in for this policy.
- Use real sibling slugs in functional mocks when a synthetic slug suffices
  (prefer `the-hcma/example-repo` or `OWNER/mock-repo`).

## Examples

```bash
# BAD — hardcoded sibling repo in shared lib
rp_log_suggest "${slug}: see fpdf for dependabot cooldown example"

# GOOD — generic pointer
rp_log_suggest "${slug}: see scripts/lib/release-age-defaults"

# BAD — probe with a real org repo name
! grep -qF 'domesti-bot' "$lib"

# GOOD — programmatic check
rp_assert_no_hardcoded_consumer_repo_names "$lib"

# BAD — fixed repo list in generic script
for repo in fpdf bunnify my-tracks; do …

# GOOD — discover from GitHub
while IFS= read -r name; do
  …
done < <(rp_discover_org_repos "$rp_DEFAULT_ORG")
```
