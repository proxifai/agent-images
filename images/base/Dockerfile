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

# Install pfai CLI for agent-platform communication.
#
# Per-arch on purpose. A single committed `pfai` used to ship here, and it was
# an aarch64 binary while CI builds these images linux/amd64 only — so every
# pfai call in entrypoint.sh returned "exec format error". Because each call
# site ends in `2>/dev/null || true`, and `command -v pfai` still succeeds, the
# failure was completely silent: no status reporting, no log streaming, no
# output upload, no PR creation. Keep both binaries in step with the platform
# (`make -C ../proxifai build-go` style cross-builds) and never collapse this
# back to one file.
ARG TARGETARCH
COPY pfai-${TARGETARCH} /usr/local/bin/pfai
# Fail the build rather than ship an unrunnable CLI again. This reads the ELF
# header's e_machine field (offset 18) instead of executing the binary: `pfai`
# runs maybeNudgeSkills on every invocation, which touches the filesystem, so
# an exec-based check could hang or fail for reasons unrelated to the arch.
# 62 = x86-64, 183 = aarch64.
RUN chmod +x /usr/local/bin/pfai \
    && _m="$(od -An -tu1 -j18 -N1 /usr/local/bin/pfai | tr -d ' ')" \
    && case "${TARGETARCH}:${_m}" in \
         amd64:62|arm64:183) echo "pfai ok: ${TARGETARCH} (e_machine=${_m})" ;; \
         *) echo "FATAL: pfai e_machine=${_m} does not match TARGETARCH=${TARGETARCH}"; exit 1 ;; \
       esac

# Generic agent entrypoint (handles clone, tool execution, push, PR for all tools)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Pre-create directories for volume mounts
RUN mkdir -p /root/.claude /etc/claude-code /workspace

WORKDIR /workspace

EXPOSE 22

CMD ["/usr/local/bin/entrypoint.sh"]
