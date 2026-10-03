#!/usr/bin/env bash
# The hook targets the other proxifai repos expose as `make hooks`,
# `make hooks-contract` and `make ci-local`. This repo has no Makefile.
#
#   .githooks/install.sh [hooks]       core.hooksPath=.githooks, chmod, missing pinned tools
#   .githooks/install.sh hooks-contract re-record .githooks/ci-contract.sha256 after
#                                       aligning the hooks with a workflow change
#   .githooks/install.sh ci-local       the full CI mirror, without pushing: every
#                                       image is built and tested
#   .githooks/install.sh uninstall      unset core.hooksPath
#
# Nothing is installed outside this clone except actionlint (`go install`).

# shellcheck source=lib/common.sh
. "$(dirname "$0")/lib/common.sh"
cd "$REPO_ROOT" || exit 1

ACTIONLINT_VERSION=v1.7.12

case "${1:-hooks}" in
  hooks)
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit .githooks/pre-push .githooks/install.sh
    printf 'git hooks installed (core.hooksPath=.githooks)\n'
    if command -v actionlint >/dev/null 2>&1; then
      printf '  actionlint   %s\n' "$(actionlint -version 2>/dev/null | head -1)"
    elif command -v go >/dev/null 2>&1; then
      printf '  installing actionlint %s ...\n' "$ACTIONLINT_VERSION"
      GOTOOLCHAIN=auto go install "github.com/rhysd/actionlint/cmd/actionlint@$ACTIONLINT_VERSION"
    else
      printf '  actionlint missing and no Go to install it: https://github.com/rhysd/actionlint\n'
    fi
    command -v docker >/dev/null 2>&1 || printf '  docker missing: pre-push cannot build the images (SKIP_DOCKER=1 to skip)\n'
    printf '  pre-commit  conflict markers, secrets, actionlint + contract, docker build --check\n'
    printf '  pre-push    build-images.yml + build-desktop-multiarch.yml: the changed images, then tests/test.sh\n'
    ;;
  hooks-contract) record_ci_contract ;;
  ci-local)       exec .githooks/pre-push < /dev/null ;;
  uninstall)      git config --unset core.hooksPath; printf 'core.hooksPath unset\n' ;;
  *) printf 'usage: %s [hooks|hooks-contract|ci-local|uninstall]\n' "$0" >&2; exit 2 ;;
esac
