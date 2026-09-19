---
description: dep-updater nested npm (single */package.json) detection invariants
globs: scripts/dep-updater,tests/dep-updater.test
alwaysApply: false
---

# dep-updater nested npm detection (required)

Python-first consumer repos may ship a single frontend under one child directory (`web/package.json`, `frontend/package.json`, …) with **no** root `package.json`. `detect_ecosystem` enables npm only when there is **exactly one** immediate `*/package.json` (multiple candidates are ambiguous and skipped).

## Must support

- **Single nested npm project** at `*/package.json` when it is the only candidate under the repo root.
- **Last `git ls-tree` line**: the nested directory often sorts last (e.g. after `uv.lock`). `git ls-tree --name-only` frequently omits a trailing newline on the final entry; feeding that into `while read` without a terminating `\n` **drops the last line** and silently disables npm for the whole repo.
- **Runner-captured git stdout**: nested discovery uses `dep_runner_git_c_stdout` (not bare `git`). Any fix must preserve runner adoption — do not reintroduce bare `git` for line-oriented probes.

## Known failure mode

- Symptom: batch log shows `Detected: python/uv, github-actions` only — no `npm (pnpm)` — while Dependabot still opens bumps under the nested directory.
- Tracking: [issue #330](https://github.com/the-hcma/repository-helpers/issues/330).

## Fix / test checklist

1. Ensure line-oriented git stdout helpers terminate with `\n` before `while read`, or use `read -r line || [[ -n "$line" ]]` at call sites.
2. Add a regression test where the sole nested `*/package.json` path is the **last** line of synthetic `ls-tree` output without a trailing newline.
3. Verify with `scripts/dep-updater --dir <python-first-clone-with-web/> --dry-run --batch` — expect `Using nested package.json at: …` and npm in `Detected:`.

## Do not

- Remove nested npm support in favour of requiring root `package.json`.
- Hardcode consumer repo names in shared libs or rules (discover at runtime; see `no-hardcoded-org-repos.mdc`).
