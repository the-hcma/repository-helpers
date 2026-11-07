# setup-tmp-layout

Org composite action: export `REPOSITORY_HELPERS_DIR` (the repository-helpers checkout GitHub downloaded to run this action) so a consumer's `.github/ci/*` wrappers can run `scripts/dev/with-tmp-layout`. The temp files of pytest, uv and pnpm then land under `$TMPDIR/<project>/<branch>/<tool>`, the same layout as local runs (repository-helpers#832).

No token and no extra clone are needed: a runner downloads the whole repository at the pinned ref to run any action in it.

```yaml
- uses: the-hcma/repository-helpers/actions/setup-tmp-layout@<sha on main>
- run: bash .github/ci/pytest-hermetic
```

Pin a full commit SHA that is on `main` (a merge commit), like [`setup-pnpm-corepack`](../setup-pnpm-corepack/README.md). The wrapper then calls `"$REPOSITORY_HELPERS_DIR/scripts/dev/with-tmp-layout" <tool> -- <command>`; without the variable it falls back to `$HOME/work/ai/repository-helpers`, and without that it runs the command unchanged.
