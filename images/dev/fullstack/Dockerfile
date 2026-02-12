# ProxifAI Dev Fullstack Image - Multi-language development environment
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Fullstack"
LABEL org.opencontainers.image.description="Multi-language environment with Node.js, Python, and build tools"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-fullstack"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install Node.js, Python, and build toolchain
RUN apk add --no-cache \
    # Node.js
    nodejs \
    npm \
    # Python
    python3 \
    py3-pip \
    py3-virtualenv \
    # Build toolchain
    gcc \
    g++ \
    musl-dev \
    python3-dev \
    libffi-dev \
    # Docker CLI (for container workflows)
    docker-cli \
    && npm install -g \
        pnpm \
        yarn \
        typescript \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        pipx \
    && pipx ensurepath \
    && rm -rf /var/cache/apk/* /tmp/* /root/.npm

ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
