# ProxifAI Cursor Image
# Based on minimal base with development tools for Cursor agent

FROM ghcr.io/henrydays/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI Cursor"
LABEL org.opencontainers.image.description="Alpine-based image for Cursor-style AI coding agent"
LABEL ai.proxifai.image.type="cursor"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="cursor"

# Install development essentials
RUN apk add --no-cache \
    nodejs \
    npm \
    python3 \
    py3-pip \
    make \
    gcc \
    g++ \
    && rm -rf /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
