# ProxifAI Claude Code Agent
# Layer 3 of 3: Base → Dev Node → Claude Code

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-node:latest

LABEL org.opencontainers.image.title="ProxifAI Claude Code"
LABEL org.opencontainers.image.description="Claude Code CLI agent on Node.js development environment"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="claude-code"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="claude-code"

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code \
    && rm -rf /root/.npm /tmp/*

# Pre-create directories for volume mounts
RUN mkdir -p /root/.claude /etc/claude-code

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
