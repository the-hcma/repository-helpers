---
description: Every gh call site, agent or first-party code, must run through scripts/gh-api
alwaysApply: true
---

# GitHub API rate-limit throttle

Every `gh` call site — PR / issue triage, review replies, CI polling, `gh api`, `gh pr` / `gh issue` reads and writes, and any first-party script or library function in this repo that shells out to `gh` — **must** run through the throttled wrapper, never `gh` directly:

```
"${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/gh-api" <gh args…>
```

so GitHub primary **and** secondary rate-limit backoff is automatic. A direct `gh` call 403s hard once the secondary limiter trips. First-party library code that already runs inside a bash process may instead source `scripts/lib/github-api-rate-limit` and call `github_api_exec_with_rate_limit_retry` directly — the same underlying backoff, without a redundant child-script fork per call. That function is also the host-wide pacing gate: concurrent callers share one quota budget, call spacing and rate-limit backoff through a state directory, so never bypass it with a raw `gh` call in a loop.

Full rationale, the two conforming shapes, the remaining quota gap for callers that bypass the wrapper (repository-helpers#664, #710), exemptions (`auth`, prompts, `--web`), and `scripts/gh-api --help` (the SSOT) — the canonical rule in repository-helpers:

<!-- github-api-throttle-canonical: @@GH_API_THROTTLE_RULE_URL@@ -->
@@GH_API_THROTTLE_RULE_URL@@
