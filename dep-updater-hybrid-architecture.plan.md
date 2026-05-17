# dep-updater — Hybrid Architecture Plan (Bash + Python)

## Status

**Proposal** — no implementation in this document. Intended as the roadmap for incremental extraction after policy logic in Bash became hard to test and maintain (e.g. vitest 4.1.6 / `@vitest/utils` partial publishes, batch-all structured reporting, `tooling-prereqs` readonly collisions).

---

## Goal

Keep **repository-helpers** dependable for daily/cron batch dependency updates while:

1. Preserving today’s strengths: thin orchestration over `git`, `gt`, `gh`, `pnpm`, `uv`, worktrees, and Graphite stacks.
2. Moving **decision/policy logic** (what to bump, what is resolvable, what to report) into a language with better data modeling and unit tests.
3. Avoiding a big-bang rewrite or coupling the maintenance tool to the Node app toolchain.

---

## Current state

| Layer | Today | Pain |
|-------|--------|------|
| **Orchestration** | Bash (`scripts/dep-updater`, `dep-updater-notifier`, `setup-service`) | Appropriate |
| **Policy** | Bash + `jq` + `awk` + temp files | Growing: registry closure, lockfile dry-runs, batch JSON reports, ecosystem failure files |
| **Tests** | Bash static tests + selective integration stubs | Hard to cover registry/install edge cases without live network |
| **AGENTS.md** | “Pure Bash”, no Python scripting | Intentional for deploy simplicity; should evolve to “Bash driver + optional Python planner” |

The script is ~5k+ lines. Recent fixes (#112–#115) are correct but illustrate the trend: each new rule adds shell complexity, shellcheck footguns, and long CI-only test gaps.

---

## Recommendation (summary)

| Keep in Bash | Extract to Python (first) |
|--------------|---------------------------|
| CLI flags, PATH bootstrap (`tooling-path`) | npm outdated / resolvability (packument, transitive exact deps, batch lockfile feasibility) |
| Worktree create/destroy, `gt` / `gh` submit | Batch-all report aggregation (JSON in/out; no log scraping) |
| Merge/CI wait loops, `ERROR: WAIT_TIMEOUT` conventions | Python/uv constraint filtering parity tests |
| Cron-friendly entrypoints | Shared “update plan” schema consumed by Bash |

**Do not** port the whole stack to **TypeScript** unless there is a product reason (shared types with app code, long-lived daemon/UI). TypeScript adds Node runtime coupling to the tool that already manages Node projects — Python is a better fit for registry/API/plan logic and matches the Python ecosystem targets we already run via `uv`.

---

## Target architecture

```text
┌─────────────────────────────────────────────────────────────┐
│  dep-updater (Bash) — driver                                │
│  • parse args, prereqs, worktree, traps                     │
│  • invoke planner → read plan JSON                          │
│  • apply bumps, commit, gt submit, poll CI/merge           │
└───────────────────────────┬─────────────────────────────────┘
                            │ plan.json (stdin/file)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  dep-updater-plan (Python, uv-managed) — brain              │
│  • discover outdated (npm / python / gha)                   │
│  • filter: resolvable, security-only, semver-only            │
│  • emit structured plan + reasons for skips                 │
└───────────────────────────┬─────────────────────────────────┘
                            │ httpx / packument / subprocess
                            ▼
                     registry, pnpm, uv (read-only probes)
```

**Contract:** Bash remains the only component that mutates git state or opens PRs. Python returns a versioned JSON plan; Bash validates schema and applies it. Failures are explicit in the plan (`skipped[]` with `reason`), not silent log lines.

---

## Phased milestones

### M0 — Document & agree (this PR)

- [x] Architecture plan (this file)
- [ ] Team sign-off on Bash-driver / Python-brain split and AGENTS.md update (follow-up PR)

### M1 — Plan schema + stub planner

- Define `dep-updater-plan.schema.json` (or documented JSON shape): ecosystems, packages, `from`/`to`, CVE flags, `skipped` with machine-readable `reason`.
- Add `scripts/dep-updater-plan` (Python package under repo, run via `uv run` from repo root).
- Stub implementation: wrap existing Bash discovery by calling `dep-updater --dry-run --report-json` **or** duplicate minimal discovery in Python — prefer **Python-native discovery** for npm only in M2 to avoid dual maintenance long term.
- Bash: optional `--plan-only` flag that prints plan JSON and exits 0 (no worktree). Default behavior unchanged.

### M2 — npm discovery & resolvability in Python

- Port logic equivalent to:
  - `npm_version_prefetch` / closure
  - `npm_pnpm_filter_outdated_lines` (batch lockfile dry-run)
  - pnpm “latest” vs `pnpm outdated --json` paths
- Unit tests with **recorded packument fixtures** (no network in CI).
- Bash calls Python for npm lines when `DEP_UPDATER_USE_PYTHON_PLAN=1` or `--python-plan` flag; parity test compares dry-run output against Bash golden files until cutover.

### M3 — Batch-all reporting in Python

- Child process writes plan result + failures; parent aggregates without scraping logs.
- Replace `DEP_UPDATER_RUN_REPORT` ad-hoc jq with schema-validated objects.

### M4 — Python ecosystem planner

- Port `py_outdated` filtering (transitive constraint checks via `uv pip install --dry-run` or `uv lock --dry-run`).
- Security audit parsing (`pip-audit` JSON).

### M5 — Cutover & trim Bash

- Default to Python planner; delete duplicated Bash policy blocks.
- Update AGENTS.md: Python allowed for `scripts/dep-updater-plan/`; Bash remains for drivers; CI runs `pytest` (or `uv run pytest`) on planner package.
- Keep `shellcheck` on Bash drivers only.

---

## What stays Bash (permanent)

- **Process glue** — traps, worktree lifecycle, `cleanup_on_error`, signal handling.
- **Graphite/GitHub CLI** — `gt create`, `gt submit`, `gh pr edit`, merge-it label, CI polling (unless `gh` gets a stable library we trust less than CLI).
- **Thin libs** — `tooling-path`, `tooling-prereqs` (or eventually shell wrappers that only set env and exec Python).
- **Cron contract** — minimal PATH, non-interactive flags, single-line `ERROR: WAIT_TIMEOUT` for batch-all.

---

## Testing strategy

| Component | Approach |
|-----------|----------|
| Python planner | `pytest` + fixture packuments (`tests/fixtures/npm/…`); no live registry in CI |
| Parity | Golden-file dry-run diff Bash vs Python until M5 |
| Bash driver | Existing `tests/*.test` static tests; shrink as policy moves out |
| Integration | Optional nightly job with network (not required for merge) |

---

## AGENTS.md changes (follow-up)

When M1 lands, update ground rules:

- Allow Python under `scripts/dep-updater-plan/` (and tests under `tests/dep-updater-plan/`).
- Require `uv` to run planner in dev/CI; document `uv sync` for that package.
- Clarify: **orchestration scripts stay Bash**; new JSON/API/graph logic goes in Python by default.

---

## Non-goals

- Full rewrite of `dep-updater` in Python or TypeScript in one PR.
- Replacing `gh` / `gt` with GitHub/Graphite APIs in application code (CLI remains source of truth).
- Node/TypeScript planner unless team explicitly chooses shared types with frontend repos.
- Running Python inside target repos (planner runs from repository-helpers only).

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Dual maintenance during migration | Feature flags; parity tests; time-boxed milestones |
| Python not on cron PATH | `uv run` from pinned helpers repo; or single-file venv committed (discouraged); document `bash -lc` pattern |
| Behavior drift | Golden dry-run files per fixture repo (my-tracks-like vitest case) |
| Larger CI | Planner tests are fast; network-free fixtures |

---

## Open questions

1. **Package layout** — `scripts/dep-updater-plan/` as uv project vs top-level `planner/` directory?
2. **Cutover flag** — env var vs `--python-plan` vs default-on after M2?
3. **gha_outdated** — stay Bash longer (YAML/sed) or move with M4?
4. **dep-updater-notifier** — consume Python plan summary for email body in M3?

---

## References

- Implementation history: [dep-updater.plan.md](./dep-updater.plan.md)
- Recent policy fixes: PRs #112 (tooling-prereqs), #113 (batch-all reporting), #115 (pnpm resolvability gating)
- Ground rules: [AGENTS.md](./AGENTS.md)
