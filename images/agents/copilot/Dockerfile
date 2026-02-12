# ProxifAI Copilot Agent
# Layer 3 of 3: Base → Dev Node → GitHub Copilot

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-node:latest

LABEL org.opencontainers.image.title="ProxifAI Copilot"
LABEL org.opencontainers.image.description="GitHub Copilot CLI agent on Node.js development environment"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="copilot"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="copilot"

# Install GitHub CLI
RUN apk add --no-cache github-cli \
    && rm -rf /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
