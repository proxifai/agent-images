#!/usr/bin/env bash
set -euo pipefail

# ProxifAI Agent Images - Build Script
# Builds all 3 layers in dependency order

REGISTRY="${REGISTRY:-proxifai}"
TAG="${TAG:-latest}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES_DIR="${DIR}/images"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}[build]${NC} $*"; }
ok()  { echo -e "${GREEN}[  ok ]${NC} $*"; }
err() { echo -e "${RED}[fail]${NC} $*"; }

build_image() {
    local path="$1"
    local name="$2"
    local tag="${REGISTRY}/${name}:${TAG}"
    log "Building ${BOLD}${tag}${NC} ..."
    if docker build \
        --build-arg BASE_REGISTRY="${REGISTRY}" \
        -t "${tag}" \
        "${IMAGES_DIR}/${path}"; then
        ok "${tag}"
    else
        err "${tag}"
        return 1
    fi
}

log "Registry: ${REGISTRY}"
log "Tag: ${TAG}"
echo ""

# Layer 1: Base
log "${BOLD}=== Layer 1: Base ===${NC}"
build_image "base" "base"
echo ""

# Layer 2: Dev Environments
log "${BOLD}=== Layer 2: Dev Environments ===${NC}"
for img in node python go rust fullstack desktop; do
    build_image "dev/${img}" "dev-${img}"
done
echo ""

# Layer 3: Agents
log "${BOLD}=== Layer 3: Agents ===${NC}"
for img in claude-code gemini-cli copilot aider cursor opencode; do
    build_image "agents/${img}" "${img}"
done
echo ""

ok "${BOLD}All images built successfully${NC}"

# Print image sizes
echo ""
log "${BOLD}Image sizes:${NC}"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" \
    | grep "^${REGISTRY}/" \
    | sort
