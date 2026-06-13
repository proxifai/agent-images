# ProxifAI DevPod — Lovable-style live preview pod.
# Layer 3 of 3: Base → Dev Node → DevPod
#
# Runs a long-lived vite dev server on /workspace. The proxifai backend
# Execs the agent CLI into this container on each user prompt; vite
# watches /workspace and HMRs the iframe at <id>-5173.proxif.ai when
# files change. See proxifai/internal/build/ for the orchestration.

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/dev-node:latest

LABEL org.opencontainers.image.title="ProxifAI DevPod"
LABEL org.opencontainers.image.description="Long-lived vite dev pod for the AI app builder"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="devpod"
LABEL ai.proxifai.image.version="0.1.0"
LABEL ai.proxifai.image.layer="3"
LABEL ai.proxifai.base-tool="devpod"

# Bun gives us a fast install + fast script runner. Vite, tailwind, etc.
# are installed per-scaffold so the image stays small and the scaffold's
# lockfile stays the source of truth.
RUN apk add --no-cache curl unzip \
    && curl -fsSL https://bun.sh/install | bash -s -- --no-cache \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun \
    && rm -rf /var/cache/apk/* /tmp/*

# Pre-seed a blank React+Vite+TS+Tailwind scaffold at /opt/scaffolds/blank.
# entrypoint.sh copies this into /workspace on first start if /workspace
# is empty. On resurrect, the existing PVC workspace is reused.
COPY scaffolds /opt/scaffolds

# Agent CLI: kubectl-exec target for proxifai's build.Service. The
# wrapper at /usr/local/bin/pfai-build-agent shells out to bun
# /opt/devpod/agent.ts; the .ts file is the LLM-driven edit loop. See
# proxifai/internal/build/service.go for the dispatcher that invokes
# this binary.
COPY agent.ts /opt/devpod/agent.ts
COPY db-introspect.ts /opt/devpod/db-introspect.ts
COPY visual-edit.ts /opt/devpod/visual-edit.ts
COPY list-files.ts /opt/devpod/list-files.ts
COPY read-file.ts /opt/devpod/read-file.ts
COPY pfai-build-agent /usr/local/bin/pfai-build-agent
RUN chmod +x /usr/local/bin/pfai-build-agent

COPY entrypoint.sh /usr/local/bin/devpod-entrypoint.sh
RUN chmod +x /usr/local/bin/devpod-entrypoint.sh

WORKDIR /workspace
EXPOSE 5173

# RestartPolicy: Always — the pod stays up across user sessions; the
# proxifai reaper tears it down explicitly when idle. Vite restarts
# itself on crash via the entrypoint's wait loop.
ENTRYPOINT ["/usr/local/bin/devpod-entrypoint.sh"]
