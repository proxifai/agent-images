#!/usr/bin/env bash
# Shared helpers for the git hooks.
#
# The hooks exist to give the same verdict locally that the repository's
# GitHub workflows give, so a push that passes here does not come back red.
# Anything that is NOT part of that contract is labelled "EXTRA" where it runs,
# so the distinction between "CI would fail this" and "we chose to check this"
# stays honest.
#
# This file is shared verbatim across the proxifai repos (proxifai,
# cluster-manager, agent-images, infrastructure, locations). Repo-specific
# logic belongs in the hooks themselves, not here.

# NOTE: deliberately no `set -u`. macOS ships bash 3.2, where expanding an empty
# array under `set -u` is an "unbound variable" error — which would abort a hook
# in exactly the common case of "nothing staged for this language".
set -o pipefail

# Portability floor is bash 3.2 (/bin/bash on macOS). No `mapfile`, no `declare
# -A`, no `${var,,}`. read_lines_into is the 3.2-safe stand-in for `mapfile -t`.
read_lines_into() {
  local __arr="$1"; shift
  local __line
  eval "$__arr=()"
  while IFS= read -r __line; do
    [ -n "$__line" ] || continue
    eval "$__arr+=(\"\$__line\")"
  done
}

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"
CONTRACT_FILE="$REPO_ROOT/.githooks/ci-contract.sha256"
CACHE_DIR="$(git rev-parse --absolute-git-dir)/ci-parity"
mkdir -p "$CACHE_DIR" 2>/dev/null

# Tools installed with `go install` (actionlint, golangci-lint) land in
# GOPATH/bin, which is often not on the PATH a git hook inherits.
if command -v go >/dev/null 2>&1; then
  PATH="$PATH:$(GOTOOLCHAIN=local go env GOPATH 2>/dev/null)/bin"
fi
export PATH

# ── output ──────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_DIM=$'\033[2m';  C_BLD=$'\033[1m';  C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_DIM=''; C_BLD=''; C_RST=''
fi

FAILED=0
step()  { printf '%s▸ %s%s\n' "$C_BLD" "$1" "$C_RST"; }
ok()    { printf '  %s✓%s %s\n' "$C_GRN" "$C_RST" "$1"; }
warn()  { printf '  %s!%s %s\n' "$C_YEL" "$C_RST" "$1"; }
fail()  { printf '  %s✗%s %s\n' "$C_RED" "$C_RST" "$1"; FAILED=1; }
info()  { printf '  %s%s%s\n' "$C_DIM" "$1" "$C_RST"; }

# Run a command, capture output, only show it on failure. Keeps a green run quiet.
run_quiet() {
  local label="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then
    ok "$label"
  else
    fail "$label"
    printf '%s\n' "$out" | sed 's/^/      /' | tail -60
  fi
  return $rc
}

# Cleanups run on exit, in reverse order of registration. A hook that starts a
# container must remove it even when a later step fails or the user hits ^C.
__CLEANUPS=":"
on_exit() {
  __CLEANUPS="$1; $__CLEANUPS"
  # shellcheck disable=SC2064
  trap "$__CLEANUPS" EXIT
  # shellcheck disable=SC2064
  trap "$__CLEANUPS; exit 130" INT TERM
}

# Seconds since the epoch, for timing a hook.
now() { date +%s; }

# ── staged / changed file selection ─────────────────────────────────────────
# --diff-filter=d drops deletions: a deleted file cannot be formatted or vetted,
# and feeding its path to a tool just produces a confusing "no such file".
staged_files() {
  git diff --cached --name-only --diff-filter=d -- "$@"
}

# Go packages touched by the staged Go files under module root $1 ("." for the
# repo root, "api" for cluster-manager), as ./-prefixed dirs relative to that
# module root, deduped.
staged_go_pkgs() {
  local mod="${1:-.}" prefix
  if [ "$mod" = "." ]; then prefix=""; else prefix="$mod/"; fi
  staged_files "${prefix}*.go" \
    | sed "s|^${prefix}||" \
    | xargs -I{} dirname {} 2>/dev/null \
    | sort -u \
    | while read -r d; do [ -d "$REPO_ROOT/$prefix$d" ] && printf './%s\n' "$d"; done
}

# ── what a push sends ───────────────────────────────────────────────────────
# Git hands pre-push the refs being pushed on stdin. read_push_refs keeps them;
# pushed_files lists every file the pushed commits change. With no stdin (for
# example `make ci-local`) nothing is known, so path-gated jobs run anyway:
# when in doubt, behave like CI would on the widest change.
PUSH_REFS=""
read_push_refs() {
  if [ ! -t 0 ]; then PUSH_REFS="$(cat)"; fi
}
pushed_files() {
  local zero=0000000000000000000000000000000000000000
  local lref lsha rref rsha base
  printf '%s\n' "$PUSH_REFS" | while read -r lref lsha rref rsha; do
    [ -n "$lsha" ] || continue
    [ "$lsha" = "$zero" ] && continue # branch deletion: nothing to check
    if [ "$rsha" = "$zero" ] || ! git cat-file -e "$rsha" 2>/dev/null; then
      base="$(git merge-base "$lsha" "$(default_remote_branch)" 2>/dev/null)"
    else
      base="$rsha"
    fi
    if [ -n "$base" ]; then
      git diff --name-only "$base" "$lsha"
    else
      git ls-tree -r --name-only "$lsha"
    fi
  done | sort -u
}
# push_touches PATTERN...: true when the push changes a path matching any
# extended-regex PATTERN, or when nothing is known about the push.
push_touches() {
  [ -n "$PUSH_REFS" ] || return 0
  local re
  re="$(printf '%s|' "$@")"; re="${re%|}"
  # Not `grep -q`: it exits at the first match, pushed_files then dies of
  # SIGPIPE, and under pipefail that turns a match into "no match".
  pushed_files | grep -E "$re" >/dev/null
}

# origin/main (or whatever origin/HEAD points at).
default_remote_branch() {
  local b
  b="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  printf '%s\n' "${b:-origin/main}"
}

# A pull request is tested as the merge of the branch into main, not the branch
# tip. If main has moved, CI can fail on a combination this hook never built.
check_up_to_date_with_main() {
  local main behind
  main="$(default_remote_branch)"
  git rev-parse -q --verify "$main" >/dev/null || { info "no $main ref — skipped the merge-base check"; return 0; }
  behind="$(git rev-list --count "HEAD..$main" 2>/dev/null || echo 0)"
  if [ "$behind" -gt 0 ]; then
    warn "$main has $behind commit(s) this branch doesn't — a PR is tested merged with them; merge or rebase to test what CI tests"
  else
    ok "contains $main"
  fi
}

# The command that runs a hook target in this repo: `make <target>` where the
# Makefile has it, else `.githooks/install.sh <target>` (repos with no Makefile).
hook_cmd() { # target
  if grep -q "^$1:" "$REPO_ROOT/Makefile" 2>/dev/null || [ ! -f "$REPO_ROOT/.githooks/install.sh" ]; then
    printf 'make %s\n' "$1"
  else
    printf '.githooks/install.sh %s\n' "$1"
  fi
}

# ── pipeline definitions ────────────────────────────────────────────────────
# GitHub refuses to run a workflow file it can't parse, and fails it on every
# push. actionlint catches that, plus expression and type errors.
lint_workflows() { # [files...] (default: every workflow)
  local files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    read_lines_into files < <(ls "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml 2>/dev/null)
  fi
  [ ${#files[@]} -gt 0 ] || return 0
  if ! command -v actionlint >/dev/null 2>&1; then
    fail 'actionlint not installed — an invalid workflow file fails on GitHub'
    info "install: $(hook_cmd hooks)   (or: go install github.com/rhysd/actionlint/cmd/actionlint@latest)"
    return 1
  fi
  run_quiet "actionlint (${#files[@]} workflow file(s))" actionlint "${files[@]}"
}

# The hooks mirror the workflows job for job. ci-contract.sha256 records the
# workflow files they were last aligned with, so a pipeline change can't land
# without someone updating the hooks to match it.
__sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
check_ci_contract() {
  local drift="" f rel cur want
  for f in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    rel=".github/workflows/$(basename "$f")"
    cur="$(__sha256 "$f" | cut -d' ' -f1)"
    want="$(awk -v p="$rel" '$2==p{print $1}' "$CONTRACT_FILE" 2>/dev/null)"
    [ "$cur" = "$want" ] || drift="$drift$rel"$'\n'
  done
  if [ -f "$CONTRACT_FILE" ]; then
    while read -r _ rel; do
      [ -n "$rel" ] && [ ! -f "$REPO_ROOT/$rel" ] && drift="$drift$rel (deleted)"$'\n'
    done < "$CONTRACT_FILE"
  fi
  if [ -n "$drift" ]; then
    fail 'pipeline changed since the hooks were last aligned with it:'
    printf '%s' "$drift" | sed 's/^/      /'
    info "mirror the change in .githooks, then re-record with: $(hook_cmd hooks-contract)"
    return 1
  fi
  ok 'hooks are aligned with every workflow file'
}
record_ci_contract() {
  (cd "$REPO_ROOT" && __sha256 .github/workflows/*.y*ml 2>/dev/null | sed 's/  \*/  /') > "$CONTRACT_FILE"
  printf 'recorded %s workflow file(s) in %s\n' "$(wc -l < "$CONTRACT_FILE" | tr -d ' ')" "${CONTRACT_FILE#"$REPO_ROOT"/}"
}

# Does this push update the default branch (where the deploy jobs run)?
push_targets_default_branch() {
  local main="refs/heads/$(default_remote_branch | sed 's|^origin/||')"
  printf '%s\n' "$PUSH_REFS" | awk '{print $3}' | grep -qx "$main"
}

# Every `secrets.NAME` a workflow uses must exist, or the job fails at the
# step that needs it (a missing LOCATIONS_BUMP_TOKEN once broke every
# image→deploy dispatch). Only names are read, through `gh`; values never
# leave GitHub. It can't tell a stale secret from a valid one.
check_workflow_secrets() {
  local repo want have missing="" s
  want="$(grep -hvE '^[[:space:]]*#' "$WORKFLOW_DIR"/*.y*ml 2>/dev/null \
    | grep -oE 'secrets\.[A-Za-z0-9_]+' | sed 's/^secrets\.//' | grep -vx GITHUB_TOKEN | sort -u)"
  [ -n "$want" ] || { ok 'workflows use no repository secrets'; return 0; }
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    warn 'gh not available — could not check that the secrets the workflows use exist'
    return 0
  fi
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"
  have=" $( { gh secret list --repo "$repo" --json name --jq '.[].name'
             gh secret list --org "${repo%%/*}" --json name --jq '.[].name'; } 2>/dev/null | tr '\n' ' ') "
  for s in $want; do
    case "$have" in *" $s "*) ;; *) missing="$missing $s" ;; esac
  done
  if [ -z "$missing" ]; then
    ok "every secret the workflows use exists ($(printf '%s' "$want" | wc -w | tr -d ' '))"
  elif push_targets_default_branch; then
    fail "missing repository secrets the main-branch jobs need:$missing"
    info "add them: gh secret set NAME --repo $repo"
  else
    warn "missing repository secrets (jobs on main will fail):$missing"
  fi
}

# ── toolchains ──────────────────────────────────────────────────────────────
# The first go-version a workflow pins, e.g. "1.25". Parsed rather than copied,
# so it cannot drift from the workflow.
workflow_go_version() { # workflow-file
  sed -n -E "s/^[[:space:]]*go-version:[[:space:]]*['\"]?([0-9]+\.[0-9]+(\.[0-9]+)?)['\"]?.*/\1/p" "$1" | head -1
}

# setup-go resolves "1.25" to the newest 1.25.x release. Resolve it the same
# way (cached for a day) so the hook builds with the exact compiler CI uses.
ci_go_toolchain() { # minor, e.g. 1.25
  local minor="$1" cache="$CACHE_DIR/go-$1" v
  if [ -f "$cache" ] && [ -n "$(find "$cache" -mtime -1 2>/dev/null)" ]; then cat "$cache"; return 0; fi
  v="$(GOTOOLCHAIN=local go list -m -versions go 2>/dev/null | tr ' ' '\n' \
        | grep -E "^${minor//./\\.}\.[0-9]+$" | sort -t. -k3 -n | tail -1)"
  if [ -n "$v" ]; then printf 'go%s\n' "$v" | tee "$cache"; return 0; fi
  [ -f "$cache" ] && cat "$cache"
}

# use_ci_go WORKFLOW: export GOTOOLCHAIN so every later go command in the hook
# runs the compiler WORKFLOW pins. Go downloads it once into the module cache.
use_ci_go() {
  local wf="$1" want tc
  want="$(workflow_go_version "$wf")"
  if [ -z "$want" ]; then fail "no go-version found in ${wf#"$REPO_ROOT"/}"; return 1; fi
  case "$want" in
    *.*.*) tc="go$want" ;;
    *)     tc="$(ci_go_toolchain "$want")" ;;
  esac
  if [ -z "$tc" ]; then
    fail "could not resolve CI's Go $want toolchain (offline and nothing cached)"
    return 1
  fi
  export GOTOOLCHAIN="$tc"
  if go version >/dev/null 2>&1; then
    ok "$(go env GOVERSION) — the toolchain CI resolves go-version \"$want\" to"
  else
    fail "could not fetch or run $tc"
    return 1
  fi
}

# ── services CI runs next to the job ────────────────────────────────────────
# start_ci_postgres IMAGE USER PASSWORD DB: a throwaway Postgres like the
# workflow's `services: postgres`, on a free local port. Sets CI_PG_URL and
# CI_PG_CONTAINER, and removes the container when the hook exits.
start_ci_postgres() {
  local image="$1" user="$2" pass="$3" db="$4" port i
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    fail "Docker isn't running — CI runs these tests against $image"
    info 'start Docker, or set HOOKS_SKIP_DB=1 to skip them (CI will still run them)'
    return 1
  fi
  CI_PG_CONTAINER="ci-parity-pg-$$"
  __CI_PG_USER="$user"; __CI_PG_DB="$db"
  if ! docker run -d --rm --name "$CI_PG_CONTAINER" \
        -e POSTGRES_USER="$user" -e POSTGRES_PASSWORD="$pass" -e POSTGRES_DB="$db" \
        -p 127.0.0.1::5432 "$image" >/dev/null 2>&1; then
    fail "could not start $image"
    return 1
  fi
  on_exit "docker rm -f $CI_PG_CONTAINER >/dev/null 2>&1"
  port="$(docker port "$CI_PG_CONTAINER" 5432/tcp | head -1 | sed 's/.*://')"
  # The image's init runs a temporary server on the unix socket only; probing
  # over TCP waits for the real one.
  for i in $(seq 1 90); do
    docker exec "$CI_PG_CONTAINER" pg_isready -h 127.0.0.1 -U "$user" -d "$db" >/dev/null 2>&1 && break
    sleep 1
  done
  if ! docker exec "$CI_PG_CONTAINER" pg_isready -h 127.0.0.1 -U "$user" -d "$db" >/dev/null 2>&1; then
    fail "$image did not become ready"
    return 1
  fi
  CI_PG_URL="postgres://$user:$pass@127.0.0.1:$port/$db?sslmode=disable"
  ok "$image ready on 127.0.0.1:$port"
}

# ci_psql SQL: run SQL in the throwaway Postgres (no local psql needed).
ci_psql() {
  docker exec -i "$CI_PG_CONTAINER" psql -v ON_ERROR_STOP=1 -tA -U "$__CI_PG_USER" -d "$__CI_PG_DB" -c "$1"
}

# ── clean checkouts ─────────────────────────────────────────────────────────
# ci_checkout NAME: a fresh checkout of HEAD, like the one a workflow job
# starts from — no node_modules, no build output, nothing untracked or
# ignored. Sets CI_CHECKOUT_DIR and removes the checkout when the hook (or the
# lane subshell) exits. Don't call it inside $(...): the cleanup would fire as
# soon as that subshell ends.
#
# Running a job in the working copy instead lets local state answer for CI:
# a parent node_modules once supplied @types/node to a package that never
# declared it, and CI's isolated job failed where the hook passed.
ci_checkout() { # name
  # Outside the repo's .git: Vite refuses to serve files under any .git
  # directory (server.fs.deny), so a checkout there fails every web test.
  local base="${TMPDIR:-/tmp}"
  local dir="${base%/}/ci-parity-$(basename "$REPO_ROOT")-$1"
  git -C "$REPO_ROOT" worktree remove --force "$dir" >/dev/null 2>&1
  rm -rf "$dir"
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1
  if ! git -C "$REPO_ROOT" worktree add --detach --quiet "$dir" HEAD >/dev/null 2>&1; then
    fail "could not create a clean checkout for $1"
    return 1
  fi
  on_exit "git -C '$REPO_ROOT' worktree remove --force '$dir' >/dev/null 2>&1"
  CI_CHECKOUT_DIR="$dir"
}

# ── docker builds ───────────────────────────────────────────────────────────
# Workflows build images for linux/amd64. Building that on an arm64 laptop
# needs emulation and takes many minutes, so the hook builds for the native
# platform: same Dockerfile, same context, same stages. Architecture-specific
# breakage is the one thing this can't see, and the hook says so.
#
# Anything after CONTEXT goes to `docker build` as-is: the --build-arg values
# the workflow passes, or an extra -t so a later build can use this image as
# its FROM (agent-images builds its dev images on the base it just built).
docker_build_check() { # label dockerfile context [docker build args...]
  local label="$1" dockerfile="$2" context="$3"
  shift 3
  if [ -n "${SKIP_DOCKER:-}" ]; then warn "SKIP_DOCKER set — skipped $label (CI will still build it)"; return 0; fi
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    fail "Docker isn't running — CI builds $label"
    info 'start Docker, or set SKIP_DOCKER=1 (CI will still build it)'
    return 1
  fi
  run_quiet "docker build $label (native $(uname -m); CI builds linux/amd64)" \
    docker build -q -f "$dockerfile" -t "ci-parity/$(basename "$REPO_ROOT"):check" "$@" "$context"
}
