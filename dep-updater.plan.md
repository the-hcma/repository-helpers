# `dep-update` Script — Implementation Plan

## Goal

A single, portable Bash script (`scripts/dep-update`) that:

1. **Discovers** outdated dependencies for npm/pnpm and/or Python projects
2. **Reports** them in dry-run mode (no side effects)
3. **Creates** a stacked Graphite PR stack — one PR per grouped or individual outdated dependency — inside a dedicated git worktree
4. **Cleans up** the worktree after the full stack is merged

**Tooling:** The script is implemented using **bash + git + gt + gh + jq + rg** — plus the ecosystem tools it invokes (`pnpm`, `pip`, `uv`, `poetry`) as external commands. No Node.js helpers, no Python scripting.

---

## CLI Interface

```
scripts/dep-update [OPTIONS]
scripts/dep-update --cleanup [--dir <path>]
scripts/dep-update --rebase [--dir <path>]

Modes:
  (no flags)          Update: create/reuse worktree, stack PRs, wait for merge, cleanup
  --dry-run           List outdated deps + exact PR plan preview; zero side effects
  --cleanup           Read saved state and clean up after stack is merged
  --rebase            Rebase existing stack on top of newest main

Options:
  --dir <path>        Project root (default: current working directory)
  --ecosystem <eco>   Force: npm | python | auto  (default: auto)
  --semver-only       npm only: update within existing semver range
  --no-wait-ci        Skip per-PR CI polling AND mergeable check; creates the full stack
                      immediately without gating. WARNING: the resulting stack may have
                      broken CI or merge conflicts. For local testing only — never use
                      for production update runs.
  --no-wait-merge     Exit after submitting stack; print --cleanup command
  -h, --help          Print usage and exit
```

---

## Tooling — JSON Parsing with `jq`

All CLI tools are invoked with **JSON output** where available, parsed with `jq`:

| Ecosystem | Command | jq filter |
|---|---|---|
| npm/pnpm | `pnpm outdated --json` | `to_entries[] \| "\(.key) \(.value.current) \(.value.latest)"` |
| Python/pip | `pip list --outdated --format=json` | `.[] \| "\(.name) \(.version) \(.latest_version)"` |
| Python/uv | `uv pip list --outdated --format=json` | same as pip |
| Python/pipenv | `pipenv run pip list --outdated --format=json` | same as pip |
| Python/poetry | `poetry show --outdated` | no stable JSON; parsed with `awk` |

> **Note:** `pnpm outdated` exits with code 1 when outdated packages are found. The script
> handles this with `set +e` / `set -e` around the call rather than triggering `set -euo pipefail`.

---

## Ecosystem Detection

Checked in `--dir` order of priority. Multiple ecosystems are both processed (npm first, then Python):

| File present | Ecosystem | Tool |
|---|---|---|
| `package.json` | npm | `pnpm` |
| `uv.lock` | Python | `uv` |
| `poetry.lock` | Python | `poetry` |
| `Pipfile.lock` | Python | `pipenv` |
| `requirements.txt` \| `pyproject.toml` | Python | `pip` |

---

## Prerequisite Checks

Prerequisite validation is split into two phases, both before any git or file-system changes:

### Phase 1 — Core tools (always required)

Checked immediately after `parse_args`, before ecosystem detection:

| Tool | Check | Error message |
|---|---|---|
| `git` | `command -v git` | `'git' is required but not found in PATH.` |
| `gt` | `command -v gt` | `'gt' (Graphite) is required. Install: https://graphite.dev/docs/install` |
| `gh` | `command -v gh` | `'gh' (GitHub CLI) is required. Install: https://cli.github.com` |
| `rg` | `command -v rg` | `'rg' (ripgrep) is required. Install: https://github.com/BurntSushi/ripgrep#installation` |
| `gh` auth | `gh auth status` | `'gh' is not authenticated. Run: gh auth login` |
| `gt` auth | `gt auth` exit code | `'gt' is not authenticated. Run: gt auth` |

In `--dry-run` mode, `gt` and `gh` auth checks are **skipped** (not needed for read-only operation).

### Phase 2 — Ecosystem tools (checked after detection)

Checked immediately after `detect_ecosystem`, before collecting outdated packages:

| Detected ecosystem | Tool checked | Error message |
|---|---|---|
| npm | `pnpm` | `'pnpm' is required for npm projects. Install: npm install -g pnpm` |
| Python/uv | `uv` | `'uv' is required for uv projects. Install: https://docs.astral.sh/uv/` |
| Python/poetry | `poetry` | `'poetry' is required for poetry projects. Install: https://python-poetry.org/docs/` |
| Python/pipenv | `pipenv` | `'pipenv' is required for Pipfile projects. Install: pip install pipenv` |
| Python/pip | `pip` or `pip3` | `'pip' is required for Python projects.` |

### Implementation sketch

```bash
check_core_prereqs() {
  local missing=0

  for tool in git gt gh; do
    if ! command -v "$tool" &>/dev/null; then
      log "ERROR: '${tool}' is required but not found in PATH."
      missing=$(( missing + 1 ))
    fi
  done

  (( missing > 0 )) && die "Install the missing tools above and retry."
}

check_auth_prereqs() {
  if ! gh auth status &>/dev/null; then
    die "'gh' is not authenticated. Run: gh auth login"
  fi
  if ! gt auth &>/dev/null; then
    die "'gt' is not authenticated. Run: gt auth"
  fi
}

check_ecosystem_prereqs() {
  local -r has_npm="$1"   # 1 | 0
  local -r py_tool="$2"   # uv | poetry | pipenv | pip | ""
  local missing=0

  if [[ "$has_npm" == '1' ]] && ! command -v pnpm &>/dev/null; then
    log "ERROR: 'pnpm' is required for npm projects. Install: npm install -g pnpm"
    missing=$(( missing + 1 ))
  fi

  if [[ -n "$py_tool" ]] && ! command -v "$py_tool" &>/dev/null; then
    if [[ "$py_tool" == 'pip' ]] && command -v pip3 &>/dev/null; then
      : # pip3 is acceptable
    else
      log "ERROR: '${py_tool}' is required. See plan for install instructions."
      missing=$(( missing + 1 ))
    fi
  fi

  (( missing > 0 )) && die "Install the missing tools above and retry."
}
```

> All missing tools are **collected and reported together** before exiting — the user sees the
> full list in one shot, not one error per run.

---

## Worktree Lifecycle

### Creation

```bash
# Adjacent sibling — avoids build-tool interference (node_modules, dist, etc.)
# e.g. /home/user/project/../project-dep-update-20260413T141800
worktree_name="${repo_name}-dep-update-$(date --utc +%Y%m%dT%H%M%S)-$$"
worktree_path="$(dirname "$project_root")/${worktree_name}"
# If path exists, append numeric suffix (-1, -2, ...) until unique
git -C "$project_root" worktree add "$worktree_path" main
```

All subsequent `git`, `gt`, `pnpm`, `pip`/`uv`/`poetry` commands run **within `$worktree_path`**.
On rerun, if `.dep-update-state` points to an existing worktree, that worktree is reused instead of creating another one.

### State File

Written to the original project root after worktree creation. Used by `--cleanup`.

**Path:** `<project_root>/.dep-update-state`

**Format** (plain key=value — no JSON, no jq):
```
worktree=/abs/path/to/project-dep-update-20260413T141800
base_branch=main
created_at=2026-04-13T14:18:00Z
branches=dep-updates/npm-commander,dep-updates/npm-express,dep-updates/py-requests
prs=45,46,47
```

Read with `rg "^key=" | cut -d= -f2-`; updated with `sed -i`.

> `.dep-update-state` is appended to `.gitignore` automatically if not already present.

### Cleanup

Runs automatically at end of update mode, or on demand via `dep-update --cleanup`:

```
→ Read .dep-update-state
→ For each PR number:
  gh api repos/<owner>/<repo>/pulls/<N> --jq '.state, .merged_at'