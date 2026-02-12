#!/bin/bash
# Build and push all ProxifAI agent images manually
# Run this script if GitHub Actions is not available

set -e

REGISTRY="ghcr.io/henrydays/agent-images"

echo "=== Logging into GitHub Container Registry ==="
echo $GITHUB_TOKEN | docker login ghcr.io -u henrydays --password-stdin

echo ""
echo "=== Building base image ==="
docker build -t $REGISTRY/base:latest images/base/
docker push $REGISTRY/base:latest

echo ""
echo "=== Building claude-code image ==="
docker build -t $REGISTRY/claude-code:latest images/claude-code/
docker push $REGISTRY/claude-code:latest

echo ""
echo "=== Building cursor image ==="
docker build -t $REGISTRY/cursor:latest images/cursor/
docker push $REGISTRY/cursor:latest

echo ""
echo "=== Building opencode image ==="
docker build -t $REGISTRY/opencode:latest images/opencode/
docker push $REGISTRY/opencode:latest

echo ""
echo "=== Building gemini-cli image ==="
docker build -t $REGISTRY/gemini-cli:latest images/gemini-cli/
docker push $REGISTRY/gemini-cli:latest

echo ""
echo "=== Building copilot image ==="
docker build -t $REGISTRY/copilot:latest images/copilot/
docker push $REGISTRY/copilot:latest

echo ""
echo "=== Building aider image ==="
docker build -t $REGISTRY/aider:latest images/aider/
docker push $REGISTRY/aider:latest

echo ""
echo "=== All images built and pushed successfully! ==="
echo ""
echo "Images available at:"
echo "  - $REGISTRY/base:latest"
echo "  - $REGISTRY/claude-code:latest"
echo "  - $REGISTRY/cursor:latest"
echo "  - $REGISTRY/opencode:latest"
echo "  - $REGISTRY/gemini-cli:latest"
echo "  - $REGISTRY/copilot:latest"
echo "  - $REGISTRY/aider:latest"
