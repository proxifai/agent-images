# ProxifAI Copilot Image
# Based on minimal base with development tools for GitHub Copilot CLI

FROM ghcr.io/proxifai/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI Copilot"
LABEL org.opencontainers.image.description="Alpine-based image for GitHub Copilot CLI agent"
LABEL ai.proxifai.image.type="copilot"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="copilot"

# Install Node.js and GitHub CLI
RUN apk add --no-cache \
    nodejs \
    npm \
    github-cli \
    && rm -rf /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
