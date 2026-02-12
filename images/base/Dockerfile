# ProxifAI Base Image - Solid developer foundation for all environments
# Layer 1 of 3: Base → Dev Environment → Agent

FROM alpine:3.21

LABEL org.opencontainers.image.title="ProxifAI Base"
LABEL org.opencontainers.image.description="Developer foundation with editors, search, git, shell tools"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="base"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="1"

# Install core developer tools in a single layer
RUN apk add --no-cache \
    # Shell
    bash \
    zsh \
    # SSH (server + client)
    openssh-server \
    openssh-client \
    # Editors
    neovim \
    nano \
    # Git
    git \
    git-lfs \
    # Search
    ripgrep \
    fd \
    # Terminal & session
    tmux \
    less \
    htop \
    tree \
    # Network
    curl \
    wget \
    ca-certificates \
    # Data processing
    jq \
    yq \
    # Archives
    tar \
    gzip \
    unzip \
    xz \
    # Build essentials
    make \
    # Debugging
    strace \
    lsof \
    # Misc
    coreutils \
    findutils \
    grep \
    shadow \
    && git lfs install \
    # Configure SSH
    && mkdir -p /var/run/sshd /root/.ssh \
    && ssh-keygen -A \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo 'PermitEmptyPasswords no' >> /etc/ssh/sshd_config \
    && echo 'root:root' | chpasswd \
    # Set bash as default shell for root
    && usermod -s /bin/bash root \
    # Cleanup
    && rm -rf /var/cache/apk/* /tmp/*

# Install pfai CLI for agent-platform communication
COPY --from=ghcr.io/proxifai/pfai:latest /pfai /usr/local/bin/pfai

# Pre-create directories for volume mounts
RUN mkdir -p /root/.claude /etc/claude-code /workspace

WORKDIR /workspace

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
