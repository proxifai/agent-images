FROM ubuntu:24.04

LABEL org.opencontainers.image.title="ProxifAI Ubuntu Desktop"
LABEL org.opencontainers.image.description="Full Ubuntu XFCE desktop with VNC, browser, dev tools"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-ubuntu-desktop"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    RESOLUTION=1920x1080x24 \
    VNC_PORT=5900 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    HOME=/root

# Install XFCE desktop, VNC, SSH, browser, dev tools in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # XFCE desktop environment
    xfce4 \
    xfce4-terminal \
    xfce4-taskmanager \
    xfce4-screenshooter \
    mousepad \
    thunar \
    ristretto \
    # Display server & VNC
    xvfb \
    x11vnc \
    x11-utils \
    dbus-x11 \
    # Browser
    firefox \
    # Fonts & theming
    fonts-dejavu-core \
    fonts-noto \
    fonts-noto-color-emoji \
    adwaita-icon-theme \
    papirus-icon-theme \
    # SSH server
    openssh-server \
    # Core CLI tools
    bash \
    zsh \
    git \
    git-lfs \
    curl \
    wget \
    htop \
    tree \
    less \
    vim \
    nano \
    tmux \
    ripgrep \
    fd-find \
    jq \
    unzip \
    xz-utils \
    ca-certificates \
    gnupg \
    lsb-release \
    locales \
    sudo \
    # Build tools
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    # Extra useful
    net-tools \
    iputils-ping \
    procps \
    lsof \
    strace \
    file \
    xdg-utils \
    && locale-gen en_US.UTF-8 \
    # Install Node.js 22 LTS
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm typescript ts-node \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure SSH
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo 'root:root' | chpasswd

# Create workspace
RUN mkdir -p /workspace /root/.config

# Copy rootfs overlay (startup script, XFCE config)
COPY rootfs/ /

# Make startup script executable
RUN chmod +x /usr/local/bin/start.sh

WORKDIR /workspace

EXPOSE 22 5900

CMD ["/usr/local/bin/start.sh"]
