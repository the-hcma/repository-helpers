# setup-actionlint

Installs a pinned actionlint release into `/usr/local/bin` for CI jobs that lint workflows.

The unpinned `curl -sSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash` pattern runs a branch-tip script and has no retry, so one bad response from github.com fails the job (a dep-updater PR was dropped that way, repository-helpers#842). This action pins the version, verifies the archive with a recorded SHA-256 before extracting it, and retries the download with linear backoff: the backoff sleeps add up to about five minutes, each transfer is capped at 60 seconds, and an overall 480-second budget bounds the whole install (about eight minutes), so give the job a timeout above that.

## Usage

Pin a full commit SHA that is on `main` of repository-helpers, then run `actionlint` as usual:

```yaml
- uses: actions/checkout@v7.0.1
- uses: the-hcma/repository-helpers/actions/setup-actionlint@<full SHA on main>
- run: actionlint
```

## Maintenance

Bump `actionlint_version` and both `actionlint_sha256` digests in `scripts/lib/ci-actionlint` together (the regeneration command is in the script header), then bump the pin in every consumer workflow.

`ACTIONLINT_DOWNLOAD_RETRIES` and `ACTIONLINT_RETRY_DELAY` override the retry window (tests set the delay to 0). A checksum mismatch is never retried.
