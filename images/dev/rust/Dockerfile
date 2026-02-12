# ProxifAI Dev Rust Image - Rust development environment
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Rust"
LABEL org.opencontainers.image.description="Rust development environment with cargo, rustfmt, clippy, and rust-analyzer"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-rust"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    g++ \
    musl-dev

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
        --default-toolchain stable \
        --component rustfmt,clippy \
    && rm -rf /tmp/*

ENV PATH="/root/.cargo/bin:${PATH}"

# Install rust-analyzer
RUN rustup component add rust-analyzer \
    && rm -rf /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
