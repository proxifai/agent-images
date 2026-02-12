# ProxifAI Dev Python Image - Python development environment
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Python"
LABEL org.opencontainers.image.description="Python development environment with pip, pipx, virtualenv, and poetry"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-python"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install Python and build dependencies for native extensions
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-virtualenv \
    gcc \
    g++ \
    musl-dev \
    python3-dev \
    libffi-dev \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        pipx \
    && pipx ensurepath \
    && pipx install poetry \
    && rm -rf /var/cache/apk/* /tmp/*

ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
