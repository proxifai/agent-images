# ProxifAI OpenCode Image
# Based on minimal base with Go and web terminal support

FROM ghcr.io/proxyfai/agent-images/base:latest

LABEL org.opencontainers.image.title="ProxifAI OpenCode"
LABEL org.opencontainers.image.description="Alpine-based image for OpenCode agent with web terminal"
LABEL org.opencontainers.image.source="https://github.com/proxyfai/agent-images"
LABEL ai.proxifai.image.type="opencode"
LABEL ai.proxifai.image.version="1.0.0"
LABEL ai.proxifai.base-tool="opencode"

# Install Go and ttyd for web terminal
RUN apk add --no-cache \
    go \
    ttyd \
    && rm -rf /var/cache/apk/* /tmp/* /root/go

# Expose SSH and web terminal ports
EXPOSE 22 3000

WORKDIR /workspace
CMD ["/usr/sbin/sshd", "-D", "-e"]
