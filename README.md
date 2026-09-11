# ProxifAI Agent Images

Container images for ProxifAI agent workspaces. Built as **three layers** — a shared
`base`, seven language/desktop `dev-*` images, and seven agent images that add one
CLI tool each. The proxifai monolith reads `manifest.json` to populate the image
picker when an agent is created.

Most images are Alpine; the two Ubuntu desktops are not (see the table).

```
agent-images/
├── manifest.json                 # THE inventory the product reads (registry, layers, sizes)
├── images/
│   ├── base/                     # layer 1 — Alpine + SSH + the `pfai` binary
│   ├── dev/                      # layer 2 — node, python, go, rust, fullstack,
│   │                             #           desktop, ubuntu-desktop, gnome-desktop
│   └── agents/                   # layer 3 — claude-code, cursor, opencode,
│                                 #           gemini-cli, copilot, aider, devpod
├── scripts/
│   ├── build.sh                  # THE local build entrypoint (all 16, in dep order)
│   └── build-and-push.sh         # STALE — wrong registry + wrong paths, do not use
├── tests/test.sh                 # label / workdir / port / tool assertions
└── .github/workflows/build-images.yml
```

## Registry

```
ghcr.io/proxifai/agent-images/<name>:latest
```

Set in `manifest.json` (`registry`) and derived in CI from `github.repository`.

## Images

Sizes are the figures recorded in `manifest.json`; they are approximate and have not
been re-measured for this README.

### Layer 1

| Image | Size | Base | Notes |
|---|---|---|---|
| `base` | ~45MB | `alpine:3.21` | sshd, zsh/bash, git + git-lfs, curl, neovim/nano, ripgrep, fd, tmux, htop, tree, jq, yq, make, strace, lsof, plus the `pfai` agent binary |

### Layer 2 — `dev-*` (all `FROM base` unless noted)

| Image | Size | Key tools |
|---|---|---|
| `dev-node` | ~150MB | node, npm, pnpm, yarn, typescript, ts-node, gcc/g++, python3 |
| `dev-python` | ~130MB | python3, pip, pipx, virtualenv, poetry, gcc |
| `dev-go` | ~400MB | go, golangci-lint, dlv, gopls, gcc |
| `dev-rust` | ~450MB | rustc, cargo, rustfmt, clippy, rust-analyzer |
| `dev-fullstack` | ~200MB | node toolchain + python toolchain + docker-cli |
| `dev-desktop` | ~1.5GB | **`FROM debian:trixie-slim`** — per-screen xfwm4/VNC/Chrome, shared tmux, Node 22, OpenCode + Claude Code — ports 22, 5900–5907, 9222–9229 |
| `dev-ubuntu-desktop` | ~1.2GB | **`FROM ubuntu:24.04`** — xfce4, firefox, thunar, mousepad, x11vnc, nodejs |
| `dev-gnome-desktop` | ~1.5GB | **`FROM ubuntu:24.04`** — gnome-flashback/panel, metacity, nautilus, gnome-terminal, firefox, x11vnc |

The Debian bot desktop and two Ubuntu desktops have `dependsOn: null` in the
manifest — they do **not** build on `base` and do not carry its tooling.

### Layer 3 — agents

| Image | Size | Built on | Base tool |
|---|---|---|---|
| `claude-code` | ~200MB | `dev-node` | `npm i -g @anthropic-ai/claude-code` |
| `gemini-cli` | ~180MB | `dev-node` | `npm i -g @anthropic-ai/gemini-cli \|\| @google/gemini-cli` (the first name does not exist; the fallback is what installs) |
| `copilot` | ~170MB | `dev-node` | `apk add github-cli` |
| `aider` | ~200MB | `dev-python` | `pipx install aider-chat` |
| `opencode` | ~420MB | `dev-go` | `go install github.com/opencode-ai/opencode@latest` + ttyd; exposes 3000 |
| `cursor` | ~210MB | `dev-fullstack` | **none installed** — the Dockerfile only relabels `dev-fullstack`. The `baseTool: cursor` field in the manifest is not backed by a binary. |
| `devpod` | ~260MB | `dev-node` | bun + a React/Vite/TS/Tailwind scaffold at `/opt/scaffolds`, `pfai-build-agent`; exposes **5173 only, no SSH**. Manifest version `0.1.0` (everything else is `2.0.0`). |

## Usage

```bash
docker pull ghcr.io/proxifai/agent-images/claude-code:latest
docker run -d -p 2222:22 ghcr.io/proxifai/agent-images/claude-code:latest
ssh root@localhost -p 2222     # password: root
```

`root:root` with `PermitRootLogin yes` + `PasswordAuthentication yes` is baked into
`images/base/Dockerfile` — these images assume an isolated per-agent network, not a
reachable host.

The default `CMD` is `entrypoint.sh` (the agent workflow runner), which starts sshd in
the background; it is not a plain SSH server. `devpod` exposes no SSH port at all.

## Manifest

`manifest.json` is the inventory the product reads:

```
https://raw.githubusercontent.com/proxifai/agent-images/main/manifest.json
```

## Building locally

Use the script — a bare `docker build` will not work for layers 2 and 3:

```bash
./scripts/build.sh              # all 16 in dependency order, linux/amd64, no push
PUSH=1 ./scripts/build.sh       # build and push
```

Why the bare command fails:

- `images/claude-code/` does not exist — agent images live under `images/agents/`.
- Every layer-2/3 Dockerfile needs `--build-arg BASE_REGISTRY=<prefix>`; the default
  `proxifai` only resolves if you tagged the parent locally under that prefix.
- `images/base/Dockerfile` hard-fails when the `pfai-${TARGETARCH}` binary's ELF arch
  does not match, so a native build on Apple Silicon produces an arm64 image the
  clusters cannot run. `build.sh` pins `--platform linux/amd64`.

`scripts/build-and-push.sh` is stale: it pushes to a different org
(`ghcr.io/henrydays/agent-images`), references the pre-reorg `images/<agent>/` paths,
omits `--build-arg BASE_REGISTRY` on most builds, and never builds the `dev-*` layer
or `devpod`. Do not use it.

## CI

`.github/workflows/build-images.yml` — *Build and Push Docker Images*.

| Trigger | Behaviour |
|---|---|
| push to `main` on `images/**` or `manifest.json` | build + push |
| pull request on `images/**` | build only, no push |
| `workflow_dispatch` | build + push |

Jobs run in layer order: `build-base` → `build-dev-images` (8-image matrix) →
`build-agent-images` (7-image matrix, `fail-fast: false`) → `test`.

Known gap: the `test` job's pull list covers 15 images and omits `devpod`, so `devpod`
is built and pushed but never tested.

## Adding an image

Adding a directory is not enough. A new image must be registered in **all** of:

1. `images/dev/<name>/` or `images/agents/<name>/` with a Dockerfile carrying the
   standard labels.
2. `manifest.json` (including `layer` and `dependsOn`).
3. The matrix in `.github/workflows/build-images.yml`.
4. The pull list in the workflow's `test` job.
5. The build loop in `scripts/build.sh`.
6. `tests/test.sh`.

`devpod` was shipped having missed several of these; the header comment in
`scripts/build.sh` records that failure mode.

## Labels

Every image carries:

- `org.opencontainers.image.title`, `.description`, `.vendor`, `.source`
- `ai.proxifai.image.type`
- `ai.proxifai.image.version` — `2.0.0` everywhere except `devpod` (`0.1.0`)
- `ai.proxifai.image.layer` — asserted throughout `tests/test.sh`

`ai.proxifai.base-tool` is present on **layer-3 images only**; `base` and the `dev-*`
images omit it.

## Known issues

- **The `pfai` binaries are backwards.** `images/base/Dockerfile:82` copies
  `pfai-${TARGETARCH}`, but the only file **tracked in git** is `images/base/pfai` — a
  67MB unstripped **aarch64** ELF that nothing reads. `pfai-amd64` (51MB) and
  `pfai-arm64` (48MB), the ones the build actually needs, are present in the working
  tree but **untracked**, and `.gitignore` excludes neither set. A fresh clone
  therefore carries 67MB of dead weight and still cannot build `base`.
- `cursor` installs no cursor tool (see the layer-3 table).

## License

MIT — see `LICENSE`.
