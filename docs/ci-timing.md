# CI timing baseline and results

Tracking for [#692](https://github.com/the-hcma/repository-helpers/issues/692) (cut PR CI from 6-8 minutes to under 3). Every PR in the stack appends an "After" row so the savings on GitHub-hosted runners stay visible.

## Baseline (before any change)

Captured 2026-10-10 from the last 100 `ci.yml` runs (2026-09-28 to 2026-10-04) via `scripts/gh-api`. Only runs that executed the heavy job are counted (guard-skipped runs finish in under 10s).

| Event | Full runs | p50 wall-clock | p95 wall-clock | Mean |
| --- | --- | --- | --- | --- |
| `pull_request` | 35 | 453s (7m33s) | 485s | 434s |
| `merge_group` | 11 | 457s (7m37s) | 480s | 449s |

Of 60 `pull_request` runs, 9 were cancelled by concurrency and 16 were guard-skipped.

Per-step means for job `shellcheck + tests` (12 sampled successful runs):

| Step | Mean | Max |
| --- | --- | --- |
| Tests | 318s | 361s |
| Shellcheck | 84s | 103s |
| Install dependencies | 9s | 19s |

Other jobs: `Guard` 0-3s, `Secret Scan` 3-4s.

Runner cost per full run is the sum of job durations, about 410s of runner time, billed as roughly 10 minutes because each job rounds up to a whole minute. The critical path equals the single `shellcheck + tests` job (347-469s), so wall-clock and runner minutes are both dominated by it.

Reproduce with:

```bash
scripts/gh-api run list --repo the-hcma/repository-helpers --workflow ci.yml --limit 100 \
  --json databaseId,event,conclusion,startedAt,updatedAt
scripts/gh-api api repos/the-hcma/repository-helpers/actions/runs/<id>/jobs
```

## Results

| Date | PR | Change | `pull_request` wall-clock | Runner time per run | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-10-10 | baseline | none | p50 453s, p95 485s | ~410s (~10 billed min) | see above |
