# setup-pnpm-corepack

Org composite action: enable Corepack pnpm from `package.json` `packageManager` and
optionally cache the pnpm store. Prefer this over `pnpm/action-setup` (especially
`version: latest` — floating tags have broken CI; see
[pnpm/action-setup#276](https://github.com/pnpm/action-setup/issues/276)).

Call **after** `actions/setup-node`. Do **not** set `cache: 'pnpm'` on `setup-node` —
this action owns store-path discovery and `actions/cache`.

## Pin policy

Consumers must pin a **full commit SHA that is on `main`** of
`the-hcma/repository-helpers` (a merge commit), not a PR branch tip or other unmerged
SHA. Pin by SHA for supply-chain integrity even when this repository is public.

Example (current `main` tip as of the merge of
[#363](https://github.com/the-hcma/repository-helpers/pull/363)):

```yaml
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
```

Dependabot may not auto-bump this composite SHA; refresh the pin periodically when the
helper changes.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `working-directory` | `.` | Directory with `package.json` and the lockfile. Use `web` for nested apps (e.g. domesti-bot) where `packageManager` lives under `web/`. |
| `cache` | `true` | Cache the pnpm store with `actions/cache`. |
| `lockfile-path` | `pnpm-lock.yaml` | Lockfile path relative to `working-directory` (cache key). |

## Examples

Root app (`package.json` / lockfile at repo root):

```yaml
- uses: actions/checkout@v7.0.1
- uses: actions/setup-node@v6.4.0
  with:
    node-version: '24'
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
- run: pnpm install --frozen-lockfile
```

Nested app (`packageManager` under `web/`, e.g. domesti-bot) — keep install in the
same directory as the action input:

```yaml
- uses: actions/checkout@v7.0.1
- uses: actions/setup-node@v6.4.0
  with:
    node-version: '24'
- uses: the-hcma/repository-helpers/actions/setup-pnpm-corepack@cde3063aa1e030fcac59bbf215131a3bd25d7908
  with:
    working-directory: web
- run: pnpm install --frozen-lockfile
  working-directory: web
```

## Path-filter gotcha

CI path filters / “deps changed” gates that only watch `package.json` and
`pnpm-lock.yaml` will **skip** pnpm jobs on workflow-only PRs (seen on
[fpdf#464](https://github.com/the-hcma/fpdf/pull/464)). When adopting this helper,
include `.github/workflows/**` (or equivalent) in those gates so adoption PRs run
install and check.

## Requirements

- Exact `"packageManager": "pnpm@X.Y.Z"` in the `package.json` under `working-directory`
- Node with Corepack available (`actions/setup-node` first)
