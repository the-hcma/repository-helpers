# GitHub custom properties

repository-helpers reads three GitHub custom properties to configure agent review per repository. They are org-level properties: the schema is defined once per organization, and each repository sets its own value. Every one is optional, an unset property means the default, and an unreadable or invalid value falls back to the default with a warning, so a repository with none of them behaves as it always did. These are the only custom properties the tooling relies on.

| Property | Type | Allowed values | When unset | Environment override | Read by |
| --- | --- | --- | --- | --- | --- |
| `agent-reviewers` | multi-select | `coderabbit`, `copilot`, `bugbot` | `coderabbit` only | `AGENT_REVIEW_QUOTA_FALLBACK_CHAIN` (comma-separated; `none` turns agent review off) | `scripts/lib/agent-review-reviewers` |
| `agent-review-enabled` | true/false | `true`, `false` | on | `AGENT_REVIEW_QUOTA_FALLBACK_CHAIN=none` | `scripts/lib/agent-review-reviewers` |
| `agent-review-max-rounds` | single-select | `0`, `1`, `2`, `3`, `4`, `5` | `3` | `AGENT_REVIEW_MAX_ROUNDS` (a non-negative integer of at most six digits, no leading zeros) | `scripts/lib/agent-review-max-rounds` |

GitHub has no numeric property type, which is why the round cap is a single-select of digit strings.

## `agent-reviewers`

Which agent reviewers watch a repository's pull requests: `coderabbit`, `copilot`, `bugbot`. The property filters the set only; the escalation order stays fixed in code (`coderabbit`, then `copilot`, then `bugbot`) and is used when an agent's daily quota is exhausted. Unset means `coderabbit` only. A value with no known reviewer, or `none` mixed into the list, warns and uses the default. `scripts/github-repo-lint` FAILS a repository whose value is not one of the allowed reviewers (`rp_check_agent_reviewers_property`).

Precedence, highest first: `AGENT_REVIEW_QUOTA_FALLBACK_CHAIN` (an explicit operator override; the property is not read, but it still cannot make the loop request a reviewer the repository's property turns off), then the property, then the default.

## `agent-review-enabled`

`false` turns agent review off for the repository: `wait` and `request` return immediately and `complete_ready` needs no agent sign-off. Unset or `true` leaves agent review on. It wins over `agent-reviewers`. A value that is not `true` or `false` FAILS the audit.

## `agent-review-max-rounds`

How many review rounds a pull request gets in `wait-for-agent-review loop` before the loop accepts it instead of waiting for yet another review (repository-helpers#861). A reviewer that finds something new on every push could otherwise hold a PR in the loop for hours.

A round is one review of a new head commit that leaves feedback to address. The loop counts rounds from the PR itself, with no state file: a head counts when an agent opened an inline thread in a review of it (the commit of that review, else the comment's original commit), or an agent's review of it has an actionable body (including findings kept in the body, such as outside the diff, nitpicks or `CHANGES_REQUESTED`). A review that finds nothing, a rate-limit or pause stub and a reply to one of our replies are not rounds, and resolved threads still count, because a round is history. "Agent" means an exact review-agent login (`copilot`, `copilot-pull-request-reviewer`, `cursor`, `coderabbit`, `coderabbitai`, `bugbot`, `chatgpt-codex-connector`, `vortex`, `mergestorm`, each with an optional `[bot]` suffix), so a human whose login merely contains one of those names never counts, and not the other bots the loop recognizes (`dependabot`, `github-actions`, `graphite`, `sonarcloud`, `codecov`, `renovate`), so a lint bot commenting through the Actions token never adds a round; `AGENT_REVIEW_ROUND_LOGIN_REGEX` overrides that list (a `|` separated list of case-insensitive patterns; anchor them yourself). The actionable-body rules are the ones the rest of the loop uses.

Precedence, highest first: `AGENT_REVIEW_MAX_ROUNDS`, then the property, then the default of `3`. `0` means no cap. An invalid `AGENT_REVIEW_MAX_ROUNDS` (not a non-negative integer, with a leading zero that bash would read as octal, or longer than six digits, which would overflow bash arithmetic) stops the loop at start-up, and a value set on the command line beats one in `~/.config/agent-review.env`, like the other `AGENT_REVIEW_*` settings; a property value outside `0` to `5` warns and uses the default, and `scripts/github-repo-lint` FAILS it.

Two limits to know. Feedback posted only as PR conversation comments has no head commit, so it is not counted as a round; the existing PR cap (`AGENT_REVIEW_PR_TIMEOUT`, 12h) still bounds such a PR, and CodeRabbit and Copilot post their findings as review threads and review bodies. And a review whose body reports `Actionable comments posted: 0` is not a round even when it lists nitpicks, because the loop does not ask anyone to triage it either: a round is what the loop would stop for.

What happens at the cap, checked every pass once CI is green and no feedback is left unanswered, and before the loop waits on any reviewer:

- The loop ends as a success with one machine-parseable line, `NOTE: AGENT_REVIEW_MAX_ROUNDS pr=#N repo=OWNER/NAME head=SHA rounds=R cap=C signed_off=0|1 reason=max-rounds`, and an operator email that says it stopped at the round cap and whether any agent had signed off. Nothing is approved on GitHub; merging stays the operator's decision, so a cap is never a silent timeout.
- Feedback that is still unanswered at the cap keeps the existing behavior: the loop stops for triage (exit 3) and you reply and resolve as usual.
- Readiness is read again at that moment, from the same status the rest of the loop uses: a PR that is not merge ready (the loop's own definition: `CLEAN`, `BLOCKED` on a required review the operator satisfies, or `UNSTABLE` while still mergeable count as ready; `BEHIND`, conflicting and the other states do not), whose CI stopped being ready, whose head moved since the loop took its snapshot, or that has unanswered feedback stays in its normal path and is looked at again on the next pass. A PR with more reviews or threads than one snapshot page holds (100) is refused by the loop with an error before any round is counted, as it always has been, and the counter also refuses to count a truncated snapshot on its own.
- A head that is only `BEHIND` its base is restacked right there (the same restack the loop does elsewhere) and looked at again on the next pass, because no reviewer will post another review to push the loop into its restack path.
- The unanswered-feedback check at the cap reads the PR comments strictly: when that read fails the PR stays in its normal path and is looked at again, so a failed read is never mistaken for "no comment pending".
- CI still has to be green: a pending run is waited on, and a failing one stops the loop as `CI_FAILED`.

## Defining the org schema

`scripts/github-repo-lint --repo OWNER/NAME --apply-fix` defines all three org properties (each is an upsert, so running it again is harmless). The audit checks the round cap schema itself, not only its name: it must be a single-select of exactly `0` to `5`, so a property that merely shares the name (a text field, a select limited to `3`, or one that also offers `7`, which the loop would reject) is reported and redefined. It needs a `gh` token with the `admin:org` scope; without it the audit prints a SUGGEST to define them in the org settings instead. GitHub rejects a `default_value` on an optional property, so the defaults live in code and an unset property is the default.

Without `--apply-fix`, `--suggest` reports a repository whose org schema lacks a property (`define org custom properties ...`), and a repository that sets an invalid value FAILS the audit under every mode.

## Setting a repository's value

In the repository: Settings, then Custom properties. Or through the API, with the throttled wrapper:

```bash
cat >/tmp/props.json <<'EOF'
{"properties":[{"property_name":"agent-review-max-rounds","value":"3"}]}
EOF
"${REPOSITORY_HELPERS_DIR:-$HOME/work/ai/repository-helpers}/scripts/gh-api" api --method PATCH \
  repos/OWNER/NAME/properties/values --input /tmp/props.json
```

Check what a repository has with `scripts/github-repo-lint --repo OWNER/NAME --suggest`, which validates every value and reports undefined properties.

## Caching and failures

The loop reads a repository's properties through a file cache so repeated passes and subshells share one API call: the value is cached for 5 minutes and a failed read for 1 minute, under `AGENT_REVIEW_REVIEWERS_CACHE_DIR` and `AGENT_REVIEW_MAX_ROUNDS_CACHE_DIR` (both default to a directory under `~/scratch/repository-helpers/`). A property that changed in the last few minutes may therefore take that long to be seen. A failed read warns once and uses the default, so an API outage never blocks a review.

## Adding another property

1. Read it in a `scripts/lib/agent-review-*` library with a `*_property_name` constant, the shared cache helpers from `agent-review-reviewers`, and an environment override that is validated when the loop starts.
2. Define and validate it in `scripts/lib/repo-practices` (`rp_apply_agent_reviewers_schema`, `rp_agent_reviewers_schema_defined`, `rp_check_agent_reviewers_property`) so `--apply-fix` defines it and a bad value fails the audit.
3. Document it in this file, in the table at the top and in its own section, and mention it next to `agent-reviewers` in `AGENTS.md`, the README, the ship-and-review skill and `etc/agent-review.env.example` where it has an environment override.
4. Add tests: the lib's resolution and fallbacks, and the repo-practices check. `tests/custom-properties-docs.test` fails when a `*_property_name` constant in `scripts/lib` is missing from this file, so an undocumented property cannot be merged.
