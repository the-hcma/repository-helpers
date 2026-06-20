# Agent review loop — implementation plan

Canonical home: **repository-helpers** (`scripts/wait-for-agent-review`, `scripts/trigger-agent-review`, `etc/agent-review.env.example`).

Consumer repos use **`.cursor/rules/pr-ship-and-review.mdc`** pointing at `${REPOSITORY_HELPERS_DIR}` — they do not copy the scripts.

**Status: workstream complete** (M1–M5 merged; closeout: worktree guard, quota preamble, operator handoff).

---

## Milestones

| Milestone | Scope | Status |
| --- | --- | --- |
| **M1** | Canonical `wait-for-agent-review` (profiles, quota fallback, CI gate, approve+email, tests, rules) | **Done** (#259, #260, #262) |
| **M2** | Dev workflow glue — one command from submit through agent review loop | **Done** (#263 `scripts/dev/ship-and-review`) |
| **M3** | Org lint **requires** valid `pr-ship-and-review.mdc` in every repo | **Done** (#260) |
| **M4** | Org rollout — cursor rule + repo-practices across `the-hcma` | **Done** (nine public repos merged; #264 calibration) |
| **M5** | Remove domesti-bot local `wait-for-copilot-review`; point at canonical flow | **Done** (#326) |
| **Closeout** | Stack worktree guard, main-worktree clean gate, cycle-start quota preamble (Copilot + Bugbot + CodeRabbit), quota-exhausted loop continues CI/thread monitoring | **Done** |

**Follow-ups outside this plan:**

- **`voxlane`** (private): run `scripts/github-repo-lint --repo the-hcma/voxlane --include-private --suggest` and merge any candidate PRs.
- **Bulk org audits** on private repos: pass `--include-private` (or `GITHUB_REPO_LINT_INCLUDE_PRIVATE=1`).

---

## Worktree discipline

All changeset work runs in a **stack worktree** (`.worktrees/<stack>-wt`), not the primary clone.

| Guard | Where |
| --- | --- |
| `dev_assert_stack_worktree` | `pre-pr-checks`, `ship-and-review` (start) |
| `dev_assert_main_worktree_clean` | `pre-pr-checks` (start + end), `ship-and-review` (start + EXIT trap) |

The primary worktree must have **empty** `git status --porcelain` before and after submit/review cycles — no stash-and-restore of pre-existing dirt.

```bash
scripts/dev/start-development --worktree <stack> --no-interactive
cd .worktrees/<stack>-wt
```

---

## Repo lint — cursor rules and `.gitignore`

`github-repo-lint` **flags** (does not auto-fix) when `.gitignore` would ignore `.cursor/rules/`. Org cursor rules must be trackable without `git add -f`.

If other `.cursor/` content should stay ignored, use:

```gitignore
.cursor/*
!.cursor/rules/
!.cursor/rules/**
```

---

## Submit hygiene — clean worktree gate

`pre-pr-checks` lints the **working tree**; CI runs **committed HEAD**. To prevent uncommitted fixes from passing locally but missing the push:

```bash
scripts/dev/ensure-submit-clean-tree   # called by submit-stack and ship-and-review before gt submit
```

Run `pre-pr-checks`, commit, then `scripts/dev/submit-stack` (or `ship-and-review`).

---

## Agent review loop — quota preamble and exhausted agents

At **`wait-for-agent-review loop`** start, the script logs daily quota status for **Copilot**, **Bugbot**, and **CodeRabbit** (local scratch caches under `~/scratch/repository-helpers/`).

When an agent's quota is exhausted, the loop **does not request** that agent. When **all** configured agents are exhausted, the loop **does not give up** — it continues CI gating, thread triage, and `check` / `complete` until merge-ready or a hard stop (threads pending, CI failure, timeout).

---

## Operator handoff (merge)

Babysit until `wait-for-agent-review check` reports `complete_ready: true`, then:

```bash
scripts/wait-for-agent-review complete --pr <number>
```

`complete` approves via `gh` and emails `AGENT_REVIEW_REPORT_TO`. **Do not** add `merge-it` or squash-merge unless the operator explicitly requests merge.

---

## M2 — Dev glue (`scripts/dev/ship-and-review`)

```bash
scripts/dev/ship-and-review [options] [GT_SUBMIT_ARGS...]
```

| Step | Command | Skip when |
| --- | --- | --- |
| 1 | `scripts/dev/pre-pr-checks` | `--no-submit` |
| 2 | `scripts/dev/ensure-submit-clean-tree` | `--no-submit` |
| 3 | `gt submit --publish --no-interactive` | `--no-submit` |
| 4 | `scripts/dev/post-pr-submission-checks` | `--no-wait-ci` adds `--no-wait` |
| 5 | `scripts/wait-for-agent-review loop --pr N` | `--no-agent-review` |

`scripts/dev/submit-stack` remains the lightweight path (pre-pr-checks + clean-tree gate + submit + PR metadata check; no CI wait, no agent loop).

---

## M4 — Org rollout (`scripts/dev/rollout-agent-review`)

```bash
scripts/dev/rollout-agent-review --suggest
scripts/dev/rollout-agent-review --apply-fix
```

Underlying tool: `scripts/github-repo-lint --all --org the-hcma [--include-private] [--suggest|--apply-fix]`.

Consumer template (`scripts/lib/repo-practices-cursor/pr-ship-and-review.mdc`): `gt submit` + `post-pr-submission-checks` + `wait-for-agent-review` — not repository-helpers-only `ship-and-review` / `submit-stack`.

---

## Success criteria

Loop `complete` requires: CI green, no pending review threads, merge-ready, fresh agent review empty on head (`complete_ready: true`). Then `complete` approves via `gh` and emails `AGENT_REVIEW_REPORT_TO`.

Non-success loop exits email + PR comment with `human reason (REASON_CODE=N)`.
