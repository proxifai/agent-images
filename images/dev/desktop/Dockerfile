# ProxifAI Bot Desktop — an X11 session per bot, on Debian.
#
# WHY DEBIAN AND NOT THE ALPINE BASE
#
# The rest of agent-images layers on proxifai/base (Alpine). This image
# deliberately does not, for three reasons that are facts about the packages
# rather than preferences:
#
#   1. xfwm4 4.20 does not exist on Alpine. Alpine 3.20 ships 4.18.0; Debian
#      trixie ships 4.20.0. Same story for the compositor: picom 12.5 here
#      against 10.2 on Alpine.
#   2. Google Chrome cannot run on musl. It is a glibc binary and there is no
#      Alpine build, so "install Chrome" is only answerable on a glibc distro.
#      Debian has it for arm64 as well as amd64, so this works on Apple
#      Silicon and on the cluster nodes alike.
#   3. Playwright's own browser downloads are glibc binaries too. On Alpine we
#      had to set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD and point it at the system
#      chromium; here the supported path is available.
#
# The cost is size — roughly 1.5GB against 540MB. That is paid once per node at
# import, and `make k3d-redeploy` pushes the app to the cluster registry rather
# than unpacking tarballs into every node, so it is not paid per deploy.
ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest AS pfai-source
FROM debian:trixie-slim

LABEL org.opencontainers.image.title="ProxifAI Bot Desktop"
LABEL org.opencontainers.image.description="Per-bot X11 session: xfwm4 + picom, VNC, Google Chrome, Playwright"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-desktop"
LABEL ai.proxifai.image.version="3.0.0"
LABEL ai.proxifai.image.layer="2"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Bot machines use the same control-plane CLI as headless agent images. In
# particular, the OpenCode setup hook invokes `pfai skills install` whenever a
# bot starts or refreshes its machine. Copy it from the architecture-matched
# base stage so desktop bots do not silently skip managed skill installation.
COPY --from=pfai-source /usr/local/bin/pfai /usr/local/bin/pfai
RUN chmod +x /usr/local/bin/pfai

# ── X11 session, compositor, VNC, and the tools the agent drives ───────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb x11-xserver-utils x11-utils xauth \
        xfwm4 xfconf picom xfce4-panel \
        x11vnc \
        xterm xfce4-terminal \
        thunar mousepad \
        adwaita-icon-theme dconf-gsettings-backend libglib2.0-bin \
        xdotool scrot imagemagick \
        fonts-dejavu-core fonts-noto-core fonts-liberation \
        dbus dbus-x11 libgl1 \
        bash git curl wget ca-certificates gnupg jq ripgrep fd-find \
        less tree procps tmux util-linux vim-tiny \
        openssh-server sudo \
        python3 python3-pip python3-venv \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# ── Google Chrome ──────────────────────────────────────────────────────────
#
# The real thing, from Google's own repository, not chromium. Installed via apt
# so its many shared-library dependencies are resolved rather than guessed at.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-chrome-stable; \
    rm -rf /var/lib/apt/lists/*; \
    google-chrome --version

# `chromium-browser` is the name the platform's tools and older scripts invoke.
# Keep it working so the browser is reachable under either name.
RUN ln -sf /usr/bin/google-chrome /usr/local/bin/chromium-browser \
    && ln -sf /usr/bin/google-chrome /usr/local/bin/chromium

# ── Node tooling ───────────────────────────────────────────────────────────
#
# Claude Code requires Node 22+. Debian trixie currently ships Node 20, so use
# the official, checksum-verified multi-architecture Node release instead of
# accepting npm's engine warning and shipping a CLI that cannot start.
ARG NODE_VERSION=22.23.2
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) node_arch=x64 ;; \
      arm64) node_arch=arm64 ;; \
      *) echo "unsupported Node.js architecture" >&2; exit 1 ;; \
    esac; \
    node_archive="node-v${NODE_VERSION}-linux-${node_arch}.tar.gz"; \
    node_base="https://nodejs.org/dist/v${NODE_VERSION}"; \
    cd /tmp; \
    curl -fsSLO "${node_base}/${node_archive}"; \
    curl -fsSL "${node_base}/SHASUMS256.txt" -o SHASUMS256.txt; \
    grep "  ${node_archive}$" SHASUMS256.txt | sha256sum -c -; \
    tar -xzf "${node_archive}" -C /usr/local --strip-components=1; \
    rm -f "${node_archive}" SHASUMS256.txt; \
    node --version; \
    npm --version

# Playwright drives the browser over CDP and needs no bundled browser of its
# own, so skip the download and point it at Chrome.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome
ARG PNPM_VERSION=10.34.5
ARG OPENCODE_VERSION=1.18.26
ARG CLAUDE_CODE_VERSION=2.1.259
RUN npm install -g --no-fund --no-audit \
        "pnpm@${PNPM_VERSION}" typescript playwright \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force

# `require('playwright')` must resolve from anywhere: browser_action runs
# `node -e` with a working directory of /tmp, and a global install sits outside
# the default module resolution path.
ENV NODE_PATH=/usr/local/lib/node_modules

# ── The user the session runs as ───────────────────────────────────────────
#
# The home directory must be OWNED by this user. When it was not, fontconfig
# could not write its cache and every X client — window manager, terminal,
# browser — died on startup, leaving the bare dark screen.
RUN useradd -m -u 1000 -s /bin/bash user \
    && echo 'user:user' | chpasswd \
    && usermod -aG sudo user \
    && echo '%sudo ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/nopasswd \
    && chmod 0440 /etc/sudoers.d/nopasswd \
    && mkdir -p /workspace && chown user:user /workspace \
    && mkdir -p /var/run/sshd && ssh-keygen -A

COPY rootfs/ /

RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/screen-session.sh /usr/local/bin/agent-chrome /usr/local/bin/agent-terminal \
    && mkdir -p /home/user/.cache/fontconfig /home/user/.config /home/user/Desktop \
    && chown -R user:user /home/user \
    && fc-cache -f >/dev/null 2>&1 || true

# ── Screen geometry ────────────────────────────────────────────────────────
#
# One container hosts several bots, each with its own X session. Screen n is
# display :(BASE_DISPLAY+n), served over VNC on (BASE_VNC_PORT+n), with Chrome
# listening for DevTools Protocol on (CDP_BASE_PORT+n). Screen 0 lands on
# :99 / 5900 / 9222, which is what the platform's instance tools expect.
ENV SCREENS=1
ENV BASE_DISPLAY=99
ENV BASE_VNC_PORT=5900
ENV CDP_BASE_PORT=9222
ENV DISPLAY=:99
ENV RESOLUTION=1920x1080x24

# A browser on each screen at startup, SUPERVISED: a bot asked to "look at this
# page" should not have to launch one first, and a browser that dies must come
# back — browser_action attaches over CDP, so a closed port is a machine that
# cannot browse until it is rebuilt. LAUNCH_BROWSER=0 for a bare desktop.
#
# Everything that starts Chrome goes through /usr/local/bin/agent-chrome, the
# dock launcher included, so there is only ever one browser and it always has
# the DevTools port open.
ENV LAUNCH_BROWSER=1
ENV BROWSER_HOME_PAGE=about:blank
# Compositing (shadows, fades). COMPOSITOR=0 disables it — worth doing over a
# slow link, since every repaint becomes VNC traffic.
ENV COMPOSITOR=1

ENV HOME=/home/user
ENV XDG_CACHE_HOME=/home/user/.cache
ENV PATH="/home/user/.local/bin:${PATH}"

WORKDIR /workspace

# 5900-5907 covers the default per-workspace screen ceiling (max_screens 8);
# 9222-9229 the matching CDP ports.
EXPOSE 22 5900-5907 9222-9229

CMD ["/usr/local/bin/start.sh"]
