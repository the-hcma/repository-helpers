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

## Decisions on the #692 plan

- **Step 1 (parallel jobs):** `ci.yml` runs `actionlint`, `bash -n + shellcheck` and `tests (shard N/4)` as `ci-part-*` jobs behind one rollup job that keeps the required context name `shellcheck + tests`. Protection discovery skips `ci-part-*`, so parts can be split or renamed without touching branch protection.
- **Step 2 (shards):** test files are sharded round-robin by `scripts/dev/run-tests --shard I/N`. The 337s `aa-github-repo-lint.test` was split into six real files (`tests/github-repo-lint-part-*.test`) that each stay under the time budget. Tests are never selected by section name or regex.
- **Step 3 (parallel shellcheck): not done.** `shellcheck` follows `source` into files that are given as inputs of the same invocation, so splitting the file list over several processes loses that context: a trial run produced 531 findings where the single process produces none. The change would also not shorten the critical path, because the shellcheck job already runs alongside the test shards. Caching the pinned binaries was skipped for the same reason: the download is a few seconds.
- **Step 4 (redundant runs): not done.** Skipping the heavy jobs on a title/body `edited` event was tried and dropped on review: a skipped required check counts as passing, and it is unverified whether GitHub lets the later skipped run mask an earlier red `shellcheck + tests` on the same head SHA. That needs a throwaway-PR experiment before it is safe. Path-gating docs-only PRs was also not done: the tests read Markdown (`AGENTS.md`, rule templates under `scripts/lib/repo-practices-agents/`, README), so a Markdown-only change can break a test. Whether `merge_group` should re-run the full matrix is left as an explicit decision for the operator, since it trades speed for the integration guarantee.
- **Step 5 (local gate):** `scripts/dev/pre-pr-checks` runs the same `scripts/dev/run-tests` with parallel jobs (default half the cores, 2 to 8, in this repository; 1 in consumer repos, whose tests may share ports or fixtures; override with `PRE_PR_CHECKS_TEST_JOBS`).
- **Step 6 (other workflows):** not started; needs approval-latency data first.

## Local measurements (10-core Mac)

| Measurement | Before | After |
| --- | --- | --- |
| Whole test suite, sequential | ~672s | n/a |
| Whole test suite via `run-tests --jobs 10` | n/a | 164s |
| `scripts/dev/pre-pr-checks` (all jobs) | ~11 min | 3m13s |

## CI results after the stack (PR #702, head 366c062)

Two `pull_request` runs on that head finished in **132s and 137s** of wall clock, against the 453s baseline p50 (about 70% faster, and under the 3-minute target).

| Job | Duration |
| --- | --- |
| `bash -n + shellcheck` | 77s |
| `tests (shard 1/4)` | 80s |
| `tests (shard 2/4)` | 82s |
| `tests (shard 3/4)` | 109s |
| `tests (shard 4/4)` | 117s |
| `actionlint` | 5s |
| `Guard` / `Secret Scan` / rollup | 3-4s / 6s / 3s |

Wall clock is now set by the slowest test shard (117s) rather than by the sum of install, shellcheck and tests.

Runner cost went **up**, not down. Each job bills in whole minutes, so the layout bills about 14 minutes per full run (shellcheck 2, four shards at 2 each, actionlint 1, guard 1, secret scan 1, rollup 1) against about 10 before, and the summed job time is about 485s against about 410s. This trades roughly 4 extra billed minutes per run for roughly 5 minutes less waiting.

Open items: the shards are balanced by file count, not time (shard 1 holds 80s of work and shard 4 holds 117s), so moving a heavy test between shards or splitting `dep-updater.test` would lower the maximum further. These are single-run observations, not a p50/p95; re-run the baseline query after more PRs have landed to get distributions.
