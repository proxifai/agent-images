# ProxifAI Gemini CLI Agent
# Layer 3 of 3: Base → Dev Node → Gemini CLI

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-node:latest

LABEL org.opencontainers.image.title="ProxifAI Gemini CLI"
LABEL org.opencontainers.image.description="Google Gemini CLI agent on Node.js development environment"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="gemini-cli"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="gemini-cli"

# Install Gemini CLI
RUN npm install -g @anthropic-ai/gemini-cli 2>/dev/null \
    || npm install -g @google/gemini-cli 2>/dev/null \
    || true

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
