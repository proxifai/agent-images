# ProxifAI Cursor Agent
# Layer 3 of 3: Base → Dev Fullstack → Cursor

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-fullstack:latest

LABEL org.opencontainers.image.title="ProxifAI Cursor"
LABEL org.opencontainers.image.description="Cursor-style AI coding agent on fullstack development environment"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="cursor"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="cursor"

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
