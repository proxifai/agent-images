FROM ubuntu:24.04

LABEL org.opencontainers.image.title="ProxifAI GNOME Desktop"
LABEL org.opencontainers.image.description="Ubuntu GNOME Flashback desktop with Nautilus, GNOME Terminal, Firefox, dev tools"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-gnome-desktop"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    RESOLUTION=1920x1080x24 \
    VNC_PORT=5900 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Install GNOME Flashback desktop, VNC, SSH, apps, dev tools in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # GNOME Flashback session (GNOME panel + metacity, no mutter/GL needed)
    gnome-session-flashback \
    gnome-panel \
    metacity \
    # GNOME apps
    nautilus \
    gnome-terminal \
    gnome-text-editor \
    gnome-system-monitor \
    gnome-screenshot \
    eog \
    evince \
    gnome-calculator \
    file-roller \
    # Display server & VNC
    xvfb \
    x11vnc \
    x11-utils \
    x11-xserver-utils \
    dbus-x11 \
    at-spi2-core \
    # Browser
    firefox \
    # Fonts & theming
    fonts-dejavu-core \
    fonts-noto \
    fonts-noto-color-emoji \
    adwaita-icon-theme \
    gnome-themes-extra \
    yaru-theme-gnome-shell \
    yaru-theme-gtk \
    yaru-theme-icon \
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

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash -u 1000 user \
    && echo 'user:user' | chpasswd \
    && usermod -aG sudo user \
    && echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user \
    && chmod 0440 /etc/sudoers.d/user

# Configure SSH (allow both root and user)
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo 'root:root' | chpasswd

# Create workspace owned by user
RUN mkdir -p /workspace && chown user:user /workspace

# Copy rootfs overlay (startup script, dconf settings)
COPY rootfs/ /

# Make startup script executable
RUN chmod +x /usr/local/bin/start.sh

ENV HOME=/home/user

WORKDIR /workspace

EXPOSE 22 5900

CMD ["/usr/local/bin/start.sh"]
