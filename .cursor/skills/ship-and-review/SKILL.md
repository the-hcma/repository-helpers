---
name: ship-and-review
description: Ship PRs with repository-helpers agent-review loop — pre-pr-checks, submit-stack/ship-and-review, CI wait, wait-for-agent-review triage (threads, issue comments, PR review bodies), CodeRabbit cooldown/full-review gate, Copilot/Bugbot quota fallback, restack, give-up, complete without self-approve. Use when shipping, submitting, babysitting a PR, agent review, PR feedback, CodeRabbit, Copilot, Bugbot, or merge-ready review loops.
---

# PR ship, agent review, and operator email

**Exit codes:** `scripts/wait-for-agent-review --help` and the script itself are the SSOT for exit codes and subcommands. This Skill summarizes operational flow; when in doubt, trust the script.

**Do not follow generic Cursor babysit / merge / resolve advice** when this Skill applies: **reply-before-resolve is required**, **no self-approve**, and **no `merge-it`** unless the user explicitly asked.

**Stack worktree only** — never implement or ship from the primary clone. See `.cursor/rules/pr-workflow.mdc`.

**Thin always-on rule:** `.cursor/rules/pr-ship-and-review.mdc` (contract + pointers).

When the user asks to **ship**, **submit**, **open a PR**, or **follow the flow**, run this sequence in a **stack worktree** (never the primary clone). See `pr-workflow.mdc` for worktree/Graphite basics.

Helper scripts:

- **`scripts/wait-for-agent-review`** — poll, triage, email (default agent: Copilot; no self-approve)
- **`scripts/trigger-agent-review`** — request a review from the configured agent

Configure `~/.config/agent-review.env` from `etc/agent-review.env.example` (`AGENT_REVIEW_REPORT_TO`, SMTP).

## 1. Local quality gates (all must pass before submit)

From the stack worktree:

```bash
scripts/dev/pre-pr-checks
```

Fix failures before committing. Do not skip hooks or push with failing gates.

## 2. Commit, submit, and monitor CI (required after every push)

Preferred (submit + **CI wait** + agent review loop):

```bash
gt create <stack>/<topic> -m 'feat: …'   # or gt modify -m '…'
scripts/dev/ship-and-review
```

Or step-by-step:

```bash
scripts/dev/submit-stack
scripts/dev/post-pr-submission-checks --pr <n>
./scripts/wait-for-agent-review loop --pr <n>
```

**After every push**, wait for GitHub Actions on the PR head and read failures before agent review or merge:

```bash
scripts/dev/post-pr-submission-checks --pr <n>
```

This polls until required checks finish. On failure it prints:

1. Failed check names + URLs (`ERROR: CI failures for PR #…`)
2. Filtered job log excerpts under **`==> CI failure details for coding agent`** (test `[FAIL]` lines, `--- results: … failed`, `ERROR:`, shell errors)

**Agent iteration loop when CI is red:**

1. Read the failure report from `post-pr-submission-checks` (or `gh run view <id> --log-failed`).
2. Fix in the stack worktree; run `scripts/dev/pre-pr-checks`.
3. Push (`gt modify` + `scripts/dev/submit-stack` or `gt submit`).
4. Re-run `scripts/dev/post-pr-submission-checks --pr <n>` until green.
5. Only then start or resume `./scripts/wait-for-agent-review loop --pr <n>`.

Do **not** skip CI monitoring with `--no-wait` / `--no-wait-ci` unless the user explicitly opts out. The agent review loop also blocks when `ci_ready` is false.

Use `scripts/dev/ship-and-review --no-agent-review` when you only want submit + CI (no loop).
Use `--no-submit --pr <n>` when the PR already exists (CI + loop only).
Use `scripts/dev/submit-stack --no-wait-ci` only when CI monitoring is handled separately.

Patch title/body if stale: `gh pr edit <n> --title … --body …`

## 3. Agent review loop (cycle + PR caps)

> **Reply before resolve (required):** For every valid agent review thread (Copilot, Bugbot, CodeRabbit, …), post an **on-thread human reply** as the authenticated operator **before** resolving. Exit code **3** means threads **lack a human reply** — resolving without replying is non-compliant. Never call `resolveReviewThread` (GraphQL) or `resolve-thread` until step 2 is done.

Prefer the built-in loop (posts a PR comment + emails on timeout give-up):

```bash
./scripts/wait-for-agent-review loop --pr <n>
```

**Early complete (nothing outstanding):** after all feedback is addressed (no pending threads, CI
green, merge ready), the loop completes as soon as it is **not** waiting on a requested Copilot/Bugbot
review and CodeRabbit’s workflow is **not** running. No mandatory idle dwell.
`AGENT_REVIEW_CYCLE_TIMEOUT` is retained for compatibility only.

**PR non-convergence cap:** `AGENT_REVIEW_PR_TIMEOUT` (default **12h**) — while review→fix→push
cycles keep iterating without reaching early-complete, give up after this wall time (exit **6**).

Manual iteration (when `loop` exits **3** for triage):

0. **Merged?** — if `status` reports `pr_merged: true`, stop (exit **0**).
1. **Status** — `./scripts/wait-for-agent-review status --pr <n>`
2. **Request** — `./scripts/trigger-agent-review --pr <n>` (or `wait-for-agent-review request`)
3. **Wait** — `./scripts/wait-for-agent-review wait --pr <n> --timeout <remaining-or-300>`
4. **Check** — `./scripts/wait-for-agent-review check --pr <n>`
   - Exit **0** (`complete_ready: true`) → §4 **complete**
   - Exit **3** → triage unaddressed threads (below)
   - Exit **4** → `restack` (below)
   - Exit **5** → fresh review but not empty yet; push fixes or wait for another review if threads are clear
   - Exit **2** → no fresh review; retry wait if cycle time remains
   - Exit **6** → PR non-convergence timeout (`give-up` already emailed + commented; idle-success
     exits **0** via `cmd_complete_idle`, not **6**)

### Triage unaddressed feedback (exit 3)

Feedback may arrive as **inline review threads**, **top-level PR issue comments** (agent or
**operator-authored** product notes), or **pull-request review bodies**. Use the same workflow:
address → respond → resolve. Probe/bot boilerplate stays excluded; triage replies that contain
`(In reply to <url>)` are not new pending items. A later unrelated operator comment does **not**
clear prior feedback — the reply must cite the target comment/review URL.

List pending items:

```bash
./scripts/wait-for-agent-review list-feedback --pr <n>
```

For each **review thread**:

1. Fix in the worktree when actionable (or skip with a brief on-thread reason).
2. **Reply on-thread** as the authenticated human — note what changed, which commit, or why skipped:
   ```bash
   ./scripts/wait-for-agent-review reply-thread --thread-id <PRRT_…> --body 'Fixed in abc1234: …'
   ```
   (GraphQL `addPullRequestReviewThreadReply`; REST `POST …/pulls/comments/{id}/replies` often returns 404.)
3. **Resolve only after step 2:** `./scripts/wait-for-agent-review resolve-thread --thread-id <PRRT_…>`

For each **issue comment** (`kind: issue_comment` in `list-feedback`):

1. Fix or skip with rationale as above.
2. **Reply** with a top-level PR comment referencing the agent comment:
   ```bash
   ./scripts/wait-for-agent-review reply-comment --comment-id <id> --body 'Fixed in abc1234: …' --pr <n>
   ```
3. **Resolve** after step 2 (tracks state locally — GitHub has no resolve API for issue comments):
   ```bash
   ./scripts/wait-for-agent-review resolve-comment --comment-id <id> --pr <n>
   ```

For each **pull request review body** (`kind: pull_request_review` — findings only in the
review summary, e.g. “outside changed lines”, with no inline threads):

1. Fix or skip with rationale as above.
2. **Reply** with a top-level PR comment referencing the review:
   ```bash
   ./scripts/wait-for-agent-review reply-comment --review-id <id> --body 'Fixed in abc1234: …' --pr <n>
   ```
3. **Resolve** after step 2 (local state, same store as issue comments, keyed `PRR_<id>`):
   ```bash
   ./scripts/wait-for-agent-review resolve-comment --review-id <id> --pr <n>
   ```

Batch resolve threads and replied issue comments / review bodies:

`./scripts/wait-for-agent-review resolve-addressed --pr <n>` (requires an existing human reply per item)

**Never** resolve via raw GraphQL/API without a human reply first.

Then: `gt modify`, `scripts/dev/pre-pr-checks`, push, **`scripts/dev/post-pr-submission-checks --pr <n>`** (wait for green CI; fix failures from the agent log report if red), and **start the next iteration**.

### Restack when BEHIND (exit 4)

```bash
./scripts/wait-for-agent-review restack --pr <n>
```

## 4. Complete (email operator; no self-approve)

Two success paths:

1. **`complete_ready`** — `check` returns **0** and `status` shows `complete_ready: true`. That requires at least one **agent sign-off on the current head** (Copilot/Bugbot empty pass, or a real CodeRabbit review body). A green CodeRabbit commit status alone is **not** enough — rate-limit stubs can still flip that status. Run:
   ```bash
   ./scripts/wait-for-agent-review complete --pr <n>
   ```
2. **Nothing outstanding** — `loop` exits **0** after sign-off, threads addressed, CI/merge green, and no in-flight waits. Same sign-off gate applies.

Both paths **email `AGENT_REVIEW_REPORT_TO`** when configured. They do **not** run `gh pr review --approve` (self-approve often fails for the PR author and is unnecessary).

Do **not** add `merge-it` unless the user explicitly confirms.

### Failure (PR non-convergence timeout, exit 6)

`loop` calls **give-up** automatically (email + PR comment). Manual:

```bash
./scripts/wait-for-agent-review give-up --pr <n> --reason "…"
```

### Per-agent quota (CodeRabbit → Copilot → Bugbot)

Daily quota caches (local calendar day) live under `~/scratch/repository-helpers/`:

| Agent | Cache file | Established by |
| --- | --- | --- |
| CodeRabbit | `coderabbit-review-quota.env` | Workflow check output / review comments |
| Copilot | `copilot-review-quota.env` | Review body heuristics on open PRs |
| Bugbot | `bugbot-review-quota.env` | `Cursor Bugbot` check output / PR comments |

When an agent is **exhausted** for the day, `loop` skips waiting on it and probes the next agent in **`AGENT_REVIEW_QUOTA_FALLBACK_CHAIN`** (default `coderabbit,copilot,bugbot`). When **all** agents in the chain are exhausted, `request` / `loop` exit **7** (give-up email + PR comment).

**CodeRabbit is on_push:** a new push starts CodeRabbit — never post `@coderabbitai review`.
If quota-limited, wait the cooldown with **poll-while-rate-limited** feedback polls
(`AGENT_REVIEW_CODERABBIT_RATE_LIMIT_POLL`, default **60s**; ceiling
`AGENT_REVIEW_CODERABBIT_RATE_LIMIT_WAIT_MAX`, default 60m; issues #366 / #369), then
`AGENT_REVIEW_CODERABBIT_POST_COOLDOWN_GRACE` (default **60s**); only then, if still no real
review on head, the loop may post a one-shot `@coderabbitai full review` (idempotent per head).
**When CodeRabbit says wait** (“More reviews will be available in N minutes”), do **not**
re-ask — keep waiting until `retry_after`; the full-review helper hard-refuses while
rate-limited. Rate-limit stubs are not reviews. Mid-cooldown human/agent feedback wakes
the loop (exit **3**).

CodeRabbit runs via its GitHub App / Actions after pushes. Copilot and Bugbot are probed with
explicit review requests on new PR heads when quota is unknown.

**Copilot timeline failures:** credit exhaustion sometimes appears only as a PR timeline event
`copilot_work_finished_failure` (GitHub App `copilot-swe-agent`) with no issue comment or review
body. Quota observe scans that timeline event for the local calendar day. Non-quota work failures
of the same event type also mark Copilot exhausted for the day (acceptable for skip caches).

**Bugbot** completion is detected via the **`Cursor Bugbot`** GitHub check on the PR head. The check **conclusion** and **output** (summary/text) drive status:

| Check signal | Meaning |
| --- | --- |
| `success` or output “no new issues” / “0 bugs reported” | Clean — `complete_ready` when no unaddressed Bugbot threads |
| `neutral` / `failure` with bugs reported | Findings — triage review comments (exit **3** or **5** while comments post) |
| output “usage limit reached” / usage or spend limit | Quota exhausted — exit **7** (give-up when no fallback remains) |
| other “couldn't run” / run failed | Check failed — exit **8** |

Use `./scripts/wait-for-agent-review request --pr <n>` with `AGENT_REVIEW_AGENT=bugbot` to request Bugbot directly.

## Quick reference — exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success / `complete_ready` / PR merged |
| 1 | Usage or prerequisite error |
| 2 | Wait: not fresh yet, pending CI, or transient mergeability (`UNSTABLE`/`UNKNOWN`) |
| 3 | Agent threads still lack a human reply |
| 4 | `BEHIND` (restack) or restack permanently failed / transient retries exhausted |
| 5 | Fresh review but agent did not report “no new comments” yet |
| 6 | PR non-convergence timeout — give-up emailed + PR comment posted (idle-success uses exit **0**) |
| 7 | All agents in quota chain exhausted — give-up emailed + PR comment posted |
| 8 | Agent GitHub check failed to run (non-quota; see check output on PR) |
| 9 | Wait idle break — no PR activity with all agent quotas exhausted (`loop` continues) |
| 10 | Required CI checks failed — fix CI before agent review or thread triage |
| 11 | Permanent merge block (`DIRTY`/`CONFLICTING`/`DRAFT`) — human intervention |
