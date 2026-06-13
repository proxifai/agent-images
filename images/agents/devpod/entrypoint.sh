#!/bin/sh
# ProxifAI DevPod entrypoint.
#
# Phase 1: seed /workspace from the bundled scaffold if empty, then run
# `bun install` + `bun run dev` on vite. The agent integration (Exec into
# this pod, edit files, stream output) lands in Phase 2.
#
# Required env (provided by build.Service.provisionAsync):
#   WORKSPACE       /workspace
# Optional env:
#   SCAFFOLD_ID     name under /opt/scaffolds (default: "blank")
#   VITE_HOST       (default: "0.0.0.0")
#   VITE_PORT       (default: 5173)
#   SEED_REPO_URL   if set, git clone overrides the bundled scaffold
#                   (Phase 2+ uses this for non-blank starting points)

set -e

WORKSPACE="${WORKSPACE:-/workspace}"
SCAFFOLD_ID="${SCAFFOLD_ID:-blank}"
VITE_HOST="${VITE_HOST:-0.0.0.0}"
VITE_PORT="${VITE_PORT:-5173}"

echo "=== ProxifAI DevPod ==="
echo "Workspace: $WORKSPACE"
echo "Scaffold:  $SCAFFOLD_ID"
echo "Vite:      ${VITE_HOST}:${VITE_PORT}"

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Seed the workspace. Three cases:
#  1) SEED_REPO_URL set + workspace empty → git clone the seed repo
#  2) workspace empty + bundled scaffold exists → cp scaffold
#  3) workspace non-empty → reuse (resurrect-on-reconnect from retained PVC)
if [ -z "$(ls -A "$WORKSPACE" 2>/dev/null)" ]; then
    if [ -n "${SEED_REPO_URL:-}" ]; then
        echo "Seeding workspace from $SEED_REPO_URL"
        git clone "$SEED_REPO_URL" .
    elif [ -d "/opt/scaffolds/$SCAFFOLD_ID" ]; then
        echo "Seeding workspace from /opt/scaffolds/$SCAFFOLD_ID"
        cp -a "/opt/scaffolds/$SCAFFOLD_ID/." "$WORKSPACE/"
    else
        echo "WARNING: no seed source — workspace will start empty"
    fi
else
    echo "Workspace not empty — reusing existing contents (resurrect path)"
fi

# Install deps. We do this every start because the cache lives on the PVC
# and so does node_modules — first-start hits the network; resurrects are
# fast because everything's already there.
if [ -f "$WORKSPACE/package.json" ]; then
    echo "bun install..."
    bun install --silent || npm install --no-audit --no-fund
fi

# Push the drizzle schema to sqlite if the scaffold has one. drizzle-kit
# is in devDependencies; absent for non-drizzle scaffolds so we guard.
if [ -f "$WORKSPACE/drizzle.config.ts" ] && [ -f "$WORKSPACE/src/db/schema.ts" ]; then
    export DATABASE_URL="${DATABASE_URL:-$WORKSPACE/data.db}"
    echo "drizzle-kit push → $DATABASE_URL"
    bun run db:push --force 2>&1 | sed 's/^/  drizzle: /' || echo "  drizzle: push failed; continuing"
fi

# Hand off to vite. Vite's HMR watcher takes care of file changes; the
# agent (Phase 2) just writes files and vite picks up automatically.
echo "Starting vite dev on ${VITE_HOST}:${VITE_PORT}"
exec bun run dev --host "$VITE_HOST" --port "$VITE_PORT" --strictPort
