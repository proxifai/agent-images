# ProxifAI Dev Go Image - Go development environment
# Layer 2 of 3: Base → Dev Environment → Agent

ARG BASE_REGISTRY=proxifai
FROM ${BASE_REGISTRY}/base:latest

LABEL org.opencontainers.image.title="ProxifAI Dev Go"
LABEL org.opencontainers.image.description="Go development environment with linting and debugging tools"
LABEL org.opencontainers.image.vendor="ProxifAI"
LABEL org.opencontainers.image.source="https://github.com/proxifai/agent-images"
LABEL ai.proxifai.image.type="dev-go"
LABEL ai.proxifai.image.version="2.0.0"
LABEL ai.proxifai.image.layer="2"

# Install Go and build dependencies
RUN apk add --no-cache \
    go \
    gcc \
    g++ \
    musl-dev

# Configure Go paths
ENV GOPATH="/root/go"
ENV GOBIN="${GOPATH}/bin"
ENV PATH="${GOBIN}:${PATH}"

# Install Go dev tools (pinned to versions compatible with Go 1.23)
RUN go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8 \
    && go install github.com/go-delve/delve/cmd/dlv@v1.24.2 \
    && go install golang.org/x/tools/gopls@v0.17.1 \
    && rm -rf /root/go/pkg /var/cache/apk/* /tmp/*

WORKDIR /workspace
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
