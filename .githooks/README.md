# Git hooks

Local gates that give the same verdict as `.github/workflows/build-images.yml`
and `build-desktop-multiarch.yml`, so a push that is green here does not come
back red on GitHub.

## Install

```bash
.githooks/install.sh                 # core.hooksPath=.githooks (+ actionlint if missing)
.githooks/install.sh ci-local        # the full mirror, without pushing: every image built and tested
.githooks/install.sh hooks-contract  # re-record the workflow fingerprint (see below)
.githooks/install.sh uninstall
```

This repo has no Makefile, so `install.sh` carries the targets the other proxifai
repos expose as `make hooks`, `make ci-local` and `make hooks-contract`.

## Job → hook step

| Workflow job | pre-push | pre-commit |
|---|---|---|
| `build-images.yml` **build-base** | `docker build images/base` | `docker build --check` on a staged Dockerfile *(EXTRA)* |
| `build-images.yml` **build-dev-images** (matrix of 8) | `docker build images/dev/<x>` with `--build-arg BASE_REGISTRY=<the base just built>` | the same `--check` |
| `build-images.yml` **build-agent-images** (matrix of 7) | `docker build images/agents/<x>` on the dev image just built | the same `--check` |
| `build-images.yml` **test** | `tests/test.sh` against the images this run built | — |
| `build-desktop-multiarch.yml` **build** | the version-LABEL check of "Resolve image names and tags" (same sed, same regex) + base and dev-desktop built for the native platform | — |
| — | `actionlint` + contract check on both workflows; warns when `origin/main` has commits you don't | `actionlint` + contract when a workflow is staged; conflict markers; secrets *(EXTRA)* |

The image list is **parsed from `build-images.yml`** (build-base's context and
each matrix `name`/`path` pair), and each image's parent from its Dockerfile's
`FROM ${BASE_REGISTRY}/<parent>:latest`. A new matrix entry is built by the hook
without anyone editing it.

## Which images a push builds

CI's `paths:` filter is `images/**` for the whole workflow, and then every
matrix image builds. Building all sixteen on every push is too slow to keep, so
the hook applies the same filter per image:

- an image builds when the push changes its context directory, or when its
  parent rebuilt (a `base` change rebuilds every dev image on it, and their
  agents — what CI does on `main`, where the new base is pushed first);
- an untouched parent that a rebuilt child needs is rebuilt too, so the child
  is built on *this* tree's parent (normally a docker cache hit, seconds);
- `build-desktop-multiarch.yml` runs when the push touches `images/base/`,
  `images/dev/desktop/` or that workflow file — its own `paths:`.

`ci-local` has no push to look at and builds and tests everything.

Images are tagged `ci-parity/agent-images/<name>:latest` and the children
are built with `BASE_REGISTRY=ci-parity/agent-images`, the local stand-in for
CI's `ghcr.io/<repo>` prefix. Nothing is pushed anywhere. Remove them with
`docker images 'ci-parity/agent-images/*' -q | xargs docker rmi`.

`tests/test.sh` takes an optional `IMAGES="a b c"` to test a subset (the rest
report as skipped). The hook sets it to the images it built; CI leaves it
unset and tests everything, as before.

Escape hatches: `SKIP_DOCKER=1` skips the builds and the image tests (each
skipped job is named); `git commit --no-verify` / `git push --no-verify` skip
everything. `git config hooks.fullOnCommit true` (or `HOOKS_FULL=1`) makes
pre-commit run the full mirror.

## What cannot be mirrored exactly

- **Architecture.** `build-images.yml` builds `linux/amd64`;
  `build-desktop-multiarch.yml` builds `linux/amd64` and `linux/arm64`. The hook
  builds the native platform only — on Apple Silicon that is exactly the
  multiarch job's arm64 leg, and not the amd64 image `build-images.yml` ships.
  Arch-specific breakage (a download URL hard-coded to one arch, a package that
  exists for one only) is the gap; `PLATFORM=linux/amd64 scripts/build.sh`
  builds the amd64 set under emulation when you need it.
- **Pull requests test main, not the PR.** On a PR, CI builds the dev images on
  the registry's `base:latest` (the PR's base is never pushed) and its `test`
  job pulls `:latest` from ghcr. The hook builds every child on the parent it
  just built and tests those images, i.e. what `main` will build after merge.
- **Upstream drift.** Many Dockerfiles install unpinned packages (`apk`, `apt`,
  `npm -g`). The docker cache keeps a layer that CI would rebuild fresh, so an
  upstream break can show in CI first. `docker builder prune` then `ci-local`
  reproduces a cold CI build.
- **`manifest.json`** is in `build-images.yml`'s `main` paths filter: a push
  that only changes it rebuilds everything in CI from unchanged Dockerfiles. The
  hook builds nothing for it (it says so) — only upstream drift could fail it.
- **`tests/`** is not in CI's paths filter: a change there first runs on the
  next `images/**` push. The hook notes it; `ci-local` runs it now.
- **`docker build --check` at commit time** resolves FROM, so it needs a local
  parent image (`ci-parity/agent-images/<parent>`, from an earlier pre-push).
  Before the first one it lints against an empty parent: parse errors are exact,
  lint warnings may be spurious. A Dockerfile that doesn't parse blocks; lint
  warnings only warn (CI's build only warns too).

## The contract

`.githooks/ci-contract.sha256` fingerprints both workflow files. If either
changes and the hooks are not updated with it, pre-push (and pre-commit, when a
workflow is staged) fails until someone mirrors the change and runs
`.githooks/install.sh hooks-contract`.

## Timing (Apple Silicon, warm docker cache)

- pre-commit: ~0.1 s with no Dockerfile or workflow staged; ~1 s per staged
  Dockerfile (`docker build --check`).
- pre-push: 0–1 s for a push with no image context; ~12–20 s for a typical
  one-image push (its parents are cache hits, then `tests/test.sh` on them);
  `ci-local` (all 16 images + the whole test suite) ~80 s. A cold cache is the
  real CI cost: the first `ci-local` took ~17 min.
