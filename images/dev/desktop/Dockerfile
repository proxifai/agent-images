# ProxifAI Dev Desktop Image - Graphical desktop with VNC access
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Desktop"
LABEL org.opencontainers.image.description="Graphical desktop with Openbox, VNC, Node.js, Python for remote desktop development"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-desktop"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install X11, VNC, window manager, and dev tools
RUN apk add --no-cache \
    # X11 display server
    xvfb \
    xorg-server \
    xf86-video-dummy \
    # VNC server
    x11vnc \
    # Window manager
    openbox \
    # Terminal emulator
    xterm \
    # Fonts
    font-noto \
    ttf-dejavu \
    # Desktop basics
    dbus \
    mesa-gl \
    # X11 utilities
    xsetroot \
    xdpyinfo \
    # Node.js
    nodejs \
    npm \
    # Python
    python3 \
    py3-pip \
    # Build toolchain
    gcc \
    g++ \
    musl-dev \
    python3-dev \
    libffi-dev \
    && npm install -g \
        pnpm \
        typescript \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        pipx \
    && pipx ensurepath \
    && rm -rf /var/cache/apk/* /tmp/* /root/.npm

# Copy rootfs overlay
COPY rootfs/ /

# Make start script executable
RUN chmod +x /usr/local/bin/start.sh

ENV DISPLAY=:99
ENV RESOLUTION=1920x1080x24
ENV VNC_PORT=5900
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace

EXPOSE 22 5900

CMD ["/usr/local/bin/start.sh"]
