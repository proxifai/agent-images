# ProxifAI OpenCode Agent
# Layer 3 of 3: Base → Dev Go → OpenCode

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-go:latest

LABEL org.opencontainers.image.title="ProxifAI OpenCode"
LABEL org.opencontainers.image.description="OpenCode agent on Go development environment with web terminal"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="opencode"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="opencode"

# Install ttyd for web terminal
RUN apk add --no-cache ttyd \
    && rm -rf /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22 3000
CMD ["/usr/sbin/sshd", "-D", "-e"]
