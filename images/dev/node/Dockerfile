# ProxifAI Dev Node Image - Node.js/TypeScript development environment
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Node"
LABEL org.opencontainers.image.description="Node.js development environment with npm, pnpm, yarn, and TypeScript"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-node"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install Node.js LTS and native build dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    python3 \
    gcc \
    g++ \
    musl-dev \
    && npm install -g \
        pnpm \
        yarn \
        typescript \
        ts-node \
    && rm -rf /var/cache/apk/* /tmp/* /root/.npm

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
