---
description: Run agent `gh` calls through repository-helpers/scripts/gh-api
alwaysApply: true
---

# GitHub API rate-limit throttle

Any agent flow that shells out to `gh` — PR / issue triage, review replies, CI
polling, `gh api`, and `gh pr` / `gh issue` reads and writes — **must** run it
through the throttled wrapper, never `gh` directly:

```
"${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/gh-api" <gh args…>
```

The wrapper applies GitHub primary **and** secondary rate-limit backoff
automatically — the same `github_api_exec_with_rate_limit_retry` logic
`wait-for-agent-review` and `github-repo-lint` use internally. A direct `gh` call
403s hard for the better part of an hour once the *secondary* limiter trips, and
`wait-for-agent-review resolve-comment`'s own verification probe fails with it.

Args, stdin, stdout, and the exit code (`125` for quota-intact fail-fast
included) pass straight through. Interactive `gh` (`auth`, prompts, `--web`) is
exempt; `scripts/gh-api -- <args>` opts in a subcommand the wrapper rejects.
`scripts/gh-api --help` is the SSOT.

<!-- github-api-throttle-canonical: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-api-throttle.md -->
Canonical rule: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-api-throttle.md
