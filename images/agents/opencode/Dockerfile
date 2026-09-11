# ProxifAI OpenCode Agent
# Layer 3 of 3: Base → Dev Go → OpenCode

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-go:latest

LABEL org.opencontainers.image.title="ProxifAI OpenCode"
LABEL org.opencontainers.image.description="OpenCode agent on Go development environment with web terminal"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="opencode"
LABEL ai.proxifai.image.version="3.0.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="opencode"

# Install ttyd for web terminal and Node.js for OpenCode provider plugins
RUN apk add --no-cache ttyd nodejs npm \
    && rm -rf /var/cache/apk/* /tmp/*

# Install the current OpenCode CLI. The previous github.com/opencode-ai/opencode
# Go module is a different, retired implementation and does not understand the
# current ~/.config/opencode/opencode.json provider contract.
ARG OPENCODE_VERSION=1.18.26
RUN npm install -g --no-fund --no-audit "opencode-ai@${OPENCODE_VERSION}" \
    && npm cache clean --force \
    && rm -rf /root/go/pkg /tmp/*

# Ship review-mode entrypoint alongside the default implement-mode one.
# entrypoint.sh dispatches to review-entrypoint.sh when
# PROXIFAI_AGENT_MODE=review (set by the trigger executor on pr.* events).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY review-entrypoint.sh /usr/local/bin/review-entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/review-entrypoint.sh

WORKDIR /workspace
EXPOSE 22 3000

# Restore entrypoint as CMD (dev-go layer overrides base CMD with sshd)
CMD ["/usr/local/bin/entrypoint.sh"]
