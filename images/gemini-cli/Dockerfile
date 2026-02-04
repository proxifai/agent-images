# ProxifAI Gemini CLI Image
# Based on minimal base with Node.js for Gemini CLI

FROM ghcr.io/henrydays/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI Gemini CLI"
LABEL org.opencontainers.image.description="Alpine-based image for Google Gemini CLI agent"
LABEL ai.proxifai.image.type="gemini-cli"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="gemini-cli"

# Install Node.js (required for Gemini CLI)
RUN apk add --no-cache \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
