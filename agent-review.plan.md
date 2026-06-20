# Agent review loop — implementation plan

Canonical home: **repository-helpers** (`scripts/wait-for-agent-review`, `scripts/trigger-agent-review`, `etc/agent-review.env.example`).

Consumer repos use **`.cursor/rules/pr-ship-and-review.mdc`** pointing at `${REPOSITORY_HELPERS_DIR}` — they do not copy the scripts.

---

## Milestones

| Milestone | Scope | Status |
| --- | --- | --- |
| **M1** | Canonical `wait-for-agent-review` (profiles, quota fallback, CI gate, approve+email, tests, rules) | **Done** (#259, #260 hardening, #262 loop-exit notify) |
| **M2** | Dev workflow glue — one command from submit through agent review loop | **In progress** (`scripts/dev/ship-and-review`) |
| **M3** | Org lint **requires** valid `pr-ship-and-review.mdc` in every repo | **Done** (#260) |
| **M4** | Org rollout — `github-repo-lint --apply-fix` across `the-hcma`; merge candidate PRs | **In progress** (`scripts/dev/rollout-agent-review`) |
| **M5** | Remove domesti-bot local `wait-for-copilot-review`; point at canonical flow | **Pending** (after M4) |

---

## M2 — Dev glue (`scripts/dev/ship-and-review`)

**Goal:** Agents and humans stop hand-chaining three commands after every PR.

```bash
scripts/dev/ship-and-review [options] [GT_SUBMIT_ARGS...]
```

| Step | Command | Skip when |
| --- | --- | --- |
| 1 | `scripts/dev/pre-pr-checks` | `--no-submit` |
| 2 | `gt submit --publish --no-interactive` | `--no-submit` |
| 3 | `scripts/dev/post-pr-submission-checks` | `--no-wait-ci` adds `--no-wait` |
| 4 | `scripts/wait-for-agent-review loop --pr N` | `--no-agent-review` |

**Flags:** `--pr N`, `--no-submit`, `--no-agent-review`, `--no-wait-ci`, `--help`.

**Exit codes:** Propagate the last failing step (same as `wait-for-agent-review loop` on step 4).

`scripts/dev/submit-stack` remains the lightweight path (submit + PR metadata check, no CI wait, no agent loop).

---

## M4 — Org rollout (`scripts/dev/rollout-agent-review`)

**Goal:** Repeatable org-wide rollout of the M3 cursor rule (and other `--apply-fix` candidates).

```bash
# Audit: list repos missing or stale pr-ship-and-review rule
scripts/dev/rollout-agent-review --suggest

# Open candidate fix PRs (Graphite stacks under .worktrees/repo-practices-candidate-fixes-wt)
scripts/dev/rollout-agent-review --apply-fix
```

Underlying tool: `scripts/github-repo-lint --all --org the-hcma [--suggest|--apply-fix]`.

**Manual follow-up:** Review and merge each candidate PR; re-run `--suggest` until clean.

---

## M5 — domesti-bot cleanup (deferred)

1. PR removing `scripts/wait-for-copilot-review` and domesti-specific env vars.
2. Sync domesti-bot `pr-ship-and-review.mdc` from the org template (same as M4).
3. Verify with `github-repo-lint --repo the-hcma/domesti-bot`.

---

## Success criteria (unchanged)

Loop `complete` requires: CI green, no pending review threads, merge-ready, fresh agent review empty on head (`complete_ready: true`). Then `complete` approves via `gh` and emails `AGENT_REVIEW_REPORT_TO`.

Non-success loop exits email + PR comment with `human reason (REASON_CODE=N)`.
