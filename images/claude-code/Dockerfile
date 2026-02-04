# ProxifAI Claude Code Image
# Based on minimal base with Node.js for Claude Code CLI

FROM ghcr.io/proxyfai/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI Claude Code"
LABEL org.opencontainers.image.description="Alpine-based image with Node.js for Claude Code agent"
LABEL ai.proxifai.image.type="claude-code"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="claude-code"

# Install Node.js (required for Claude Code CLI)
RUN apk add --no-cache \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/* /tmp/*

# Pre-install Claude Code CLI globally (optional - can be done at runtime)
# RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
