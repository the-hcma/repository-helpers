#!/usr/bin/env bash
# .cursor/install.sh — Cloud Agent environment bootstrap for repository-helpers.
#
# Installs the CLI tools the repository's CI and scripts/dev/pre-pr-checks require
# but that are not present on the Cursor default base image: shellcheck,
# actionlint, and gitleaks. bash, git, gh, jq, rg, node, and npm already ship
# with the base image.
#
# This script is idempotent (safe to re-run): each tool is installed only when it
# is missing or pinned to a different version. It is non-interactive and must
# terminate. Do not add dev servers, tests, or migrations here.
set -euo pipefail

# Pins mirror .github/workflows/ci.yml and scripts/lib/ci-secret-scan so the
# environment matches CI. Bump alongside those sources.
shellcheck_version='0.11.0'
actionlint_version='1.7.9'
gitleaks_version='8.30.1'
readonly shellcheck_version actionlint_version gitleaks_version

bin_dir='/usr/local/bin'
readonly bin_dir

log() {
  printf '[install] %s\n' "$*"
}

arch_amd64_only() {
  local arch
  arch="$(uname -m)"
  if [[ "$arch" != 'x86_64' ]]; then
    printf '[install] ERROR: unsupported architecture: %s (expected x86_64)\n' "$arch" >&2
    return 1
  fi
}

# tool_matches <binary> <expected-version-substring>
# True when the tool is on PATH and reports the expected version.
tool_matches() {
  local -r binary="$1"
  local -r want="$2"
  command -v "$binary" >/dev/null 2>&1 || return 1
  "$binary" --version 2>&1 | grep -Fq "$want"
}

install_shellcheck() {
  if tool_matches shellcheck "$shellcheck_version"; then
    log "shellcheck ${shellcheck_version} already installed"
    return 0
  fi
  log "installing shellcheck ${shellcheck_version}"
  local tmpdir url
  tmpdir="$(mktemp -d)"
  url="https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.linux.x86_64.tar.xz"
  curl -fSL --retry 3 --retry-delay 2 -o "${tmpdir}/shellcheck.tar.xz" "$url"
  tar -xJf "${tmpdir}/shellcheck.tar.xz" -C "$tmpdir"
  sudo install -m 0755 "${tmpdir}/shellcheck-v${shellcheck_version}/shellcheck" "${bin_dir}/shellcheck"
  rm -rf "$tmpdir"
}

install_actionlint() {
  if tool_matches actionlint "$actionlint_version"; then
    log "actionlint ${actionlint_version} already installed"
    return 0
  fi
  log "installing actionlint ${actionlint_version}"
  local tmpdir url
  tmpdir="$(mktemp -d)"
  url="https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_linux_amd64.tar.gz"
  curl -fSL --retry 3 --retry-delay 2 -o "${tmpdir}/actionlint.tar.gz" "$url"
  tar -xzf "${tmpdir}/actionlint.tar.gz" -C "$tmpdir" actionlint
  sudo install -m 0755 "${tmpdir}/actionlint" "${bin_dir}/actionlint"
  rm -rf "$tmpdir"
}

install_gitleaks() {
  if tool_matches gitleaks "$gitleaks_version"; then
    log "gitleaks ${gitleaks_version} already installed"
    return 0
  fi
  log "installing gitleaks ${gitleaks_version}"
  local tmpdir url
  tmpdir="$(mktemp -d)"
  url="https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_version}/gitleaks_${gitleaks_version}_linux_x64.tar.gz"
  curl -fSL --retry 3 --retry-delay 2 -o "${tmpdir}/gitleaks.tar.gz" "$url"
  tar -xzf "${tmpdir}/gitleaks.tar.gz" -C "$tmpdir" gitleaks
  sudo install -m 0755 "${tmpdir}/gitleaks" "${bin_dir}/gitleaks"
  rm -rf "$tmpdir"
}

main() {
  arch_amd64_only
  install_shellcheck
  install_actionlint
  install_gitleaks
  log 'versions:'
  shellcheck --version | awk '/version:/{print "  shellcheck " $2}'
  actionlint --version | head -n1 | awk '{print "  actionlint " $1}'
  gitleaks version 2>/dev/null | awk '{print "  gitleaks " $1}'
  log 'done'
}

main "$@"
