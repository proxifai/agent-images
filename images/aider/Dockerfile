# ProxifAI Aider Image
# Based on minimal base with Python for Aider AI coding assistant

FROM ghcr.io/proxyfai/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI Aider"
LABEL org.opencontainers.image.description="Alpine-based image for Aider AI pair programming agent"
LABEL ai.proxifai.image.type="aider"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="aider"

# Install Python and pip
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-virtualenv \
    && rm -rf /var/cache/apk/* /tmp/*

# Pre-install aider (optional - can be done at runtime)
# RUN pip3 install --no-cache-dir aider-chat

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
