# ProxifAI Aider Agent
# Layer 3 of 3: Base → Dev Python → Aider

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-python:latest

LABEL org.opencontainers.image.title="ProxifAI Aider"
LABEL org.opencontainers.image.description="Aider AI pair programming agent on Python development environment"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="aider"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="aider"

# Install aider-chat
RUN pipx install aider-chat \
    && rm -rf /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
