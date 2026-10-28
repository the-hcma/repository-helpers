---
description: End-to-end PR workflow — worktree, checks, Copilot, babysit
alwaysApply: true
---

# PR workflow (repository-helpers)

**Stacking tool:** read `.github/stacking-tool` first (see `.cursor/rules/stacking-tool.mdc`). This repo trials **`gh-stack`**; use `gh stack` / `.agents/skills/gh-stack/SKILL.md` instead of `gt create` when the marker is `gh-stack`. Prefer `scripts/dev/submit-stack` either way.

Follow this sequence for every PR unless the user explicitly overrides.

## 1. Worktree and branch

From the **repository root** (not the primary clone for edits):

```bash
scripts/dev/start-development --worktree <stack-name> --no-interactive
cd .worktrees/<stack-name>-wt
gh stack init <stack-name>/<topic>
```

Never implement on the main worktree (see `main-worktree-off-limits.mdc`).

## 2. Implement and verify locally

```bash
scripts/dev/pre-pr-checks
```

Must exit 0 before submit. Note the `==> pre-pr-checks passed` line for the PR Test plan.

## 3. Submit

Prefer:

```bash
scripts/dev/submit-stack
```

Not bare `gt submit` without pre-pr-checks.

## 4. Post-submit CI (monitor after every push)

```bash
scripts/dev/post-pr-submission-checks --pr <number>
```

**Required for coding agents:** wait until required checks on the **current PR head** are green. On failure, the script prints **`==> CI failure details for coding agent`** with filtered log lines — fix those in the worktree, re-run `pre-pr-checks`, push, and repeat until CI passes.

When a check is **WAITING** on a protected environment (`github-repo-lint`, `dep-updater`), **approve it on the operator's behalf** — `gh` is the operator. `post-pr-submission-checks` calls `scripts/dev/approve-pending-deployments`. Do not wait for a human to click Approve in the Actions UI. If that prints **`ERROR: ENVIRONMENT_APPROVAL_FAILED`**, raise it to the operator immediately — do not keep waiting.

`scripts/dev/submit-stack` runs this automatically (waits by default). Use `--no-wait-ci` only when monitoring separately.

Do not start the agent review loop or treat the PR as merge-ready while CI is red.

## 5. Agent review loop

Follow **`.agents/rules/pr-ship-and-review.md`** (also summarized in [AGENTS.md](../../AGENTS.md#agent-review-after-submit); Cursor shim `.cursor/rules/pr-ship-and-review.mdc`).

Prefer the built-in loop over manual `wait` / `check` iteration:

```bash
scripts/wait-for-agent-review loop --pr <number>
```

Or end-to-end from submit:

```bash
scripts/dev/ship-and-review
```

Manual steps when triaging exit **3** (threads lack a human reply):

```bash
scripts/trigger-agent-review --pr <number>
scripts/wait-for-agent-review wait --pr <number> --timeout 300
scripts/wait-for-agent-review check --pr <number>
scripts/wait-for-agent-review complete --pr <number>   # when complete_ready
```

## 6. Babysit until merge-ready

Until merge-ready:

1. Triage agent / Bugbot comments — fix valid issues, then push (`git commit` + `gh stack submit --auto --remote origin`).
2. Re-run `scripts/dev/pre-pr-checks` after fixes.
3. Re-run `scripts/dev/post-pr-submission-checks --pr <number>` and fix any CI failures surfaced in the agent log report.
4. Resolve merge conflicts if base moved (`gh stack rebase --remote origin` / `gh stack sync --remote origin`, or `scripts/wait-for-agent-review restack`).

Do not merge manually. Merge only after the user explicitly confirms, and only with `scripts/dev/merge-stack --pr <n>` (from the PR's worktree; in a consumer repo `${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/dev/merge-stack --pr <n>`): it picks the right command for the repository's merge setup (`gh stack merge` for a stacked PR, the merge queue or auto-merge otherwise) and confirms the enqueue. For a PR in a gh stack it lands the top PR and every open PR below it, so name those PRs and get confirmation for the whole stack first. Do not call `gh pr merge` or `gh stack merge` by hand, do not add the `merge-it` label, and do not pipe the command through `tail` or `head`: read its exit status and output.

### Closing the issue

Say in the PR description whether the merge should close the issue. Default, unless the repository's own `AGENTS.md` states a different convention (that wins):

1. A PR that completes an issue puts `Closes #N.` in its description as its own sentence, so the merge closes the issue. For an issue in another repository, qualify it: `Closes OWNER/REPOSITORY#N.`, because a bare `#N` means an issue in the PR's own repository.
2. A PR that is only one step of a larger issue says `Part of #N.` and does not close it (for an issue in another repository write `Part of OWNER/REPOSITORY#N.`). The last PR of the series closes the issue, and it must target the default branch when it merges: GitHub ignores a closing keyword on a PR into any other branch (for example a lower layer of a stack), so close the issue explicitly after the work lands.
3. A PR with a closing keyword is merged only after the user agrees the issue is done, because the merge closes it. The merge confirmation this workflow already requires covers that.

Avoid applying a "no closing keywords" convention to every PR regardless of whether it finishes the issue: finished issues then stay open and need a manual close pass. Spell the keyword as `.agents/rules/github-content-formatting.md` item 3 requires.

## 7. Notify user

When the PR is green and review feedback is addressed, summarize for the user: PR URL, what changed, CI status, and any remaining manual steps (e.g. deploy on a host).
