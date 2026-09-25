---
description: Every gh call site, agent or first-party code, must run through scripts/gh-api
alwaysApply: true
---

# GitHub API rate-limit throttle

Any `gh` call — PR / issue triage, review replies, CI polling, `gh api`, and
`gh pr` / `gh issue` reads and writes — **must** run through the throttled
wrapper, never `gh` directly. This applies to **every call site**, not just an
agent's own ad-hoc actions: a first-party script or library function added to
this repo (or a consumer repo) that shells out to `gh` is bound by this rule
exactly the same as an agent typing a command, whether a human or an agent
wrote that code. There are two conforming shapes, not one:

- **A one-off call** (an agent's own action, or a small script): shell out to
  the wrapper —

  ```
  "${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/gh-api" <gh args…>
  ```

- **First-party library code that already runs inside a bash process** (e.g.
  `wait-for-agent-review`, `github-repo-lint`): source
  `scripts/lib/github-api-rate-limit` and call
  `github_api_exec_with_rate_limit_retry <label> -- gh <args…>` directly —
  the exact function `scripts/gh-api` itself is a thin CLI wrapper around.
  Sourcing it directly avoids a redundant child-script fork per call; it is
  not a bypass, since it's the same backoff logic either way.

A bare, unwrapped `gh api`/`gh pr`/`gh issue` call — one that goes through
neither of the above — is the violation this rule exists to catch, regardless
of which shape the surrounding code takes.

The wrapper (and the library function underneath it) applies GitHub primary
**and** secondary rate-limit backoff automatically. A direct `gh` call 403s
hard for the better part of an hour once the *secondary* limiter trips, and
`wait-for-agent-review resolve-comment`'s own verification probe fails with it.

Known gap, not yet solved by either shape above: every consumer of one
personal `gh` token's shared hourly quota — concurrent `scripts/gh-api` calls,
a sustained `wait-for-agent-review` poll, and even a wholly separate process
authenticated as the same identity — retries/backs off independently, with no
shared, cross-process visibility into how close that one shared budget is to
exhaustion. See
[repository-helpers#664](https://github.com/the-hcma/repository-helpers/issues/664).

Args, stdin, stdout, and the exit code (`125` for quota-intact fail-fast
included) pass straight through. Interactive `gh` (`auth`, prompts, `--web`) is
exempt; `scripts/gh-api -- <args>` opts in a subcommand the wrapper rejects.
`scripts/gh-api --help` is the SSOT.

<!-- github-api-throttle-canonical: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-api-throttle.md -->
Canonical rule: https://github.com/the-hcma/repository-helpers/blob/main/.agents/rules/github-api-throttle.md
