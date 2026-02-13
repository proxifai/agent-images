#!/usr/bin/env bash
set -euo pipefail

# ProxifAI Agent Images - Automated Test Suite
# Validates all tools are present in each layer

REGISTRY="${REGISTRY:-proxifai}"
TAG="${TAG:-latest}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
ERRORS=()

log()  { echo -e "${BLUE}[test]${NC} $*"; }
ok()   { echo -e "  ${GREEN}✓${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $*"; FAIL=$((FAIL + 1)); ERRORS+=("$*"); }
skip() { echo -e "  ${YELLOW}⊘${NC} $*"; SKIP=$((SKIP + 1)); }
header() { echo -e "\n${BOLD}$*${NC}"; }

# Run a command inside a container and check exit code
run_in() {
    local image="$1"
    shift
    docker run --rm "${REGISTRY}/${image}:${TAG}" sh -c "$*" >/dev/null 2>&1
}

# Check if a command exists in the image
assert_cmd() {
    local image="$1"
    local cmd="$2"
    local desc="${3:-${cmd}}"
    if run_in "$image" "command -v ${cmd}"; then
        ok "${desc}"
    else
        fail "${image}: ${desc} not found"
    fi
}

# Check command produces expected output
assert_cmd_output() {
    local image="$1"
    local cmd="$2"
    local pattern="$3"
    local desc="${4:-${cmd}}"
    local output
    if output=$(docker run --rm "${REGISTRY}/${image}:${TAG}" sh -c "${cmd}" 2>&1) && echo "$output" | grep -qE "$pattern"; then
        ok "${desc}"
    else
        fail "${image}: ${desc} (expected pattern '${pattern}', got '${output}')"
    fi
}

# Check if image exists
assert_image_exists() {
    local image="$1"
    if docker image inspect "${REGISTRY}/${image}:${TAG}" >/dev/null 2>&1; then
        ok "Image ${image} exists"
        return 0
    else
        fail "Image ${image} does not exist - skipping tests"
        return 1
    fi
}

# Check label value
assert_label() {
    local image="$1"
    local label="$2"
    local expected="$3"
    local actual
    actual=$(docker inspect --format "{{index .Config.Labels \"${label}\"}}" "${REGISTRY}/${image}:${TAG}" 2>/dev/null || echo "")
    if [ "$actual" = "$expected" ]; then
        ok "Label ${label}=${expected}"
    else
        fail "${image}: Label ${label} expected '${expected}', got '${actual}'"
    fi
}

# Check workdir
assert_workdir() {
    local image="$1"
    local expected="$2"
    local actual
    actual=$(docker inspect --format '{{.Config.WorkingDir}}' "${REGISTRY}/${image}:${TAG}" 2>/dev/null || echo "")
    if [ "$actual" = "$expected" ]; then
        ok "Workdir is ${expected}"
    else
        fail "${image}: Workdir expected '${expected}', got '${actual}'"
    fi
}

# Check exposed port
assert_port() {
    local image="$1"
    local port="$2"
    if docker inspect --format '{{json .Config.ExposedPorts}}' "${REGISTRY}/${image}:${TAG}" 2>/dev/null | grep -q "${port}/tcp"; then
        ok "Port ${port} exposed"
    else
        fail "${image}: Port ${port} not exposed"
    fi
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ProxifAI Agent Images - Test Suite v2.0   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

########################################
# LAYER 1: BASE
########################################
header "━━━ Layer 1: base ━━━"

if assert_image_exists "base"; then
    # Metadata
    log "Checking metadata..."
    assert_label "base" "ai.proxifai.image.layer" "1"
    assert_label "base" "ai.proxifai.image.version" "2.0.0"
    assert_workdir "base" "/workspace"
    assert_port "base" "22"

    # Shells
    log "Checking shells..."
    assert_cmd "base" "bash" "bash"
    assert_cmd "base" "zsh" "zsh"

    # SSH
    log "Checking SSH..."
    assert_cmd "base" "sshd" "openssh-server (sshd)"
    assert_cmd "base" "ssh" "openssh-client (ssh)"

    # Editors
    log "Checking editors..."
    assert_cmd "base" "nvim" "neovim"
    assert_cmd "base" "nano" "nano"

    # Git
    log "Checking git..."
    assert_cmd "base" "git" "git"
    assert_cmd "base" "git-lfs" "git-lfs"

    # Search
    log "Checking search tools..."
    assert_cmd "base" "rg" "ripgrep"
    assert_cmd "base" "fd" "fd"

    # Terminal tools
    log "Checking terminal tools..."
    assert_cmd "base" "tmux" "tmux"
    assert_cmd "base" "less" "less"
    assert_cmd "base" "htop" "htop"
    assert_cmd "base" "tree" "tree"

    # Network
    log "Checking network tools..."
    assert_cmd "base" "curl" "curl"
    assert_cmd "base" "wget" "wget"

    # Data processing
    log "Checking data tools..."
    assert_cmd "base" "jq" "jq"
    assert_cmd "base" "yq" "yq"

    # Archives
    log "Checking archive tools..."
    assert_cmd "base" "tar" "tar"
    assert_cmd "base" "gzip" "gzip"
    assert_cmd "base" "unzip" "unzip"
    assert_cmd "base" "xz" "xz"

    # Build
    log "Checking build tools..."
    assert_cmd "base" "make" "make"

    # Debug
    log "Checking debug tools..."
    assert_cmd "base" "strace" "strace"
    assert_cmd "base" "lsof" "lsof"

    # Default shell should be bash
    log "Checking default shell..."
    assert_cmd_output "base" "grep '^root:' /etc/passwd" "/bin/bash" "default shell is bash"
fi

########################################
# LAYER 2: DEV ENVIRONMENTS
########################################

header "━━━ Layer 2: dev-node ━━━"
if assert_image_exists "dev-node"; then
    assert_label "dev-node" "ai.proxifai.image.layer" "2"

    # Inherits base tools
    log "Checking base inheritance..."
    assert_cmd "dev-node" "nvim" "neovim (from base)"
    assert_cmd "dev-node" "rg" "ripgrep (from base)"
    assert_cmd "dev-node" "tmux" "tmux (from base)"
    assert_cmd "dev-node" "jq" "jq (from base)"

    # Node.js ecosystem
    log "Checking Node.js ecosystem..."
    assert_cmd "dev-node" "node" "node"
    assert_cmd "dev-node" "npm" "npm"
    assert_cmd "dev-node" "pnpm" "pnpm"
    assert_cmd "dev-node" "yarn" "yarn"
    assert_cmd "dev-node" "tsc" "typescript (tsc)"
    assert_cmd "dev-node" "ts-node" "ts-node"

    # Native build deps
    log "Checking native build deps..."
    assert_cmd "dev-node" "gcc" "gcc"
    assert_cmd "dev-node" "g++" "g++"
    assert_cmd "dev-node" "python3" "python3 (for node-gyp)"
fi

header "━━━ Layer 2: dev-python ━━━"
if assert_image_exists "dev-python"; then
    assert_label "dev-python" "ai.proxifai.image.layer" "2"

    log "Checking base inheritance..."
    assert_cmd "dev-python" "nvim" "neovim (from base)"
    assert_cmd "dev-python" "rg" "ripgrep (from base)"
    assert_cmd "dev-python" "tmux" "tmux (from base)"

    log "Checking Python ecosystem..."
    assert_cmd "dev-python" "python3" "python3"
    assert_cmd "dev-python" "pip" "pip"
    assert_cmd "dev-python" "pipx" "pipx"
    assert_cmd "dev-python" "virtualenv" "virtualenv"
    assert_cmd "dev-python" "poetry" "poetry"

    log "Checking native build deps..."
    assert_cmd "dev-python" "gcc" "gcc"
fi

header "━━━ Layer 2: dev-go ━━━"
if assert_image_exists "dev-go"; then
    assert_label "dev-go" "ai.proxifai.image.layer" "2"

    log "Checking base inheritance..."
    assert_cmd "dev-go" "nvim" "neovim (from base)"
    assert_cmd "dev-go" "rg" "ripgrep (from base)"

    log "Checking Go ecosystem..."
    assert_cmd "dev-go" "go" "go"
    assert_cmd "dev-go" "golangci-lint" "golangci-lint"
    assert_cmd "dev-go" "dlv" "dlv (delve debugger)"
    assert_cmd "dev-go" "gopls" "gopls"

    log "Checking Go env..."
    assert_cmd_output "dev-go" "go env GOPATH" "/root/go" "GOPATH=/root/go"
fi

header "━━━ Layer 2: dev-rust ━━━"
if assert_image_exists "dev-rust"; then
    assert_label "dev-rust" "ai.proxifai.image.layer" "2"

    log "Checking base inheritance..."
    assert_cmd "dev-rust" "nvim" "neovim (from base)"
    assert_cmd "dev-rust" "rg" "ripgrep (from base)"

    log "Checking Rust ecosystem..."
    assert_cmd "dev-rust" "rustc" "rustc"
    assert_cmd "dev-rust" "cargo" "cargo"
    assert_cmd "dev-rust" "rustfmt" "rustfmt"
    assert_cmd "dev-rust" "clippy-driver" "clippy"
    assert_cmd "dev-rust" "rust-analyzer" "rust-analyzer"
    assert_cmd "dev-rust" "rustup" "rustup"
fi

header "━━━ Layer 2: dev-fullstack ━━━"
if assert_image_exists "dev-fullstack"; then
    assert_label "dev-fullstack" "ai.proxifai.image.layer" "2"

    log "Checking base inheritance..."
    assert_cmd "dev-fullstack" "nvim" "neovim (from base)"
    assert_cmd "dev-fullstack" "tmux" "tmux (from base)"

    log "Checking Node.js..."
    assert_cmd "dev-fullstack" "node" "node"
    assert_cmd "dev-fullstack" "npm" "npm"
    assert_cmd "dev-fullstack" "pnpm" "pnpm"
    assert_cmd "dev-fullstack" "tsc" "typescript (tsc)"

    log "Checking Python..."
    assert_cmd "dev-fullstack" "python3" "python3"
    assert_cmd "dev-fullstack" "pip" "pip"
    assert_cmd "dev-fullstack" "pipx" "pipx"

    log "Checking Docker CLI..."
    assert_cmd "dev-fullstack" "docker" "docker-cli"

    log "Checking build toolchain..."
    assert_cmd "dev-fullstack" "gcc" "gcc"
    assert_cmd "dev-fullstack" "g++" "g++"
fi

header "━━━ Layer 2: dev-desktop ━━━"
if assert_image_exists "dev-desktop"; then
    assert_label "dev-desktop" "ai.proxifai.image.layer" "2"

    log "Checking base inheritance..."
    assert_cmd "dev-desktop" "nvim" "neovim (from base)"
    assert_cmd "dev-desktop" "rg" "ripgrep (from base)"
    assert_cmd "dev-desktop" "tmux" "tmux (from base)"

    log "Checking X11 and VNC..."
    assert_cmd "dev-desktop" "Xvfb" "Xvfb"
    assert_cmd "dev-desktop" "x11vnc" "x11vnc"
    assert_cmd "dev-desktop" "openbox" "openbox"
    assert_cmd "dev-desktop" "xterm" "xterm"

    log "Checking Node.js..."
    assert_cmd "dev-desktop" "node" "node"
    assert_cmd "dev-desktop" "npm" "npm"
    assert_cmd "dev-desktop" "pnpm" "pnpm"

    log "Checking Python..."
    assert_cmd "dev-desktop" "python3" "python3"

    log "Checking ports..."
    assert_port "dev-desktop" "22"
    assert_port "dev-desktop" "5900"
fi

header "━━━ Layer 2: dev-ubuntu-desktop ━━━"
if assert_image_exists "dev-ubuntu-desktop"; then
    assert_label "dev-ubuntu-desktop" "ai.proxifai.image.layer" "2"

    log "Checking XFCE desktop..."
    assert_cmd "dev-ubuntu-desktop" "startxfce4" "xfce4"
    assert_cmd "dev-ubuntu-desktop" "xfce4-terminal" "xfce4-terminal"
    assert_cmd "dev-ubuntu-desktop" "thunar" "thunar (file manager)"
    assert_cmd "dev-ubuntu-desktop" "mousepad" "mousepad (text editor)"

    log "Checking X11 and VNC..."
    assert_cmd "dev-ubuntu-desktop" "Xvfb" "Xvfb"
    assert_cmd "dev-ubuntu-desktop" "x11vnc" "x11vnc"

    log "Checking browser..."
    assert_cmd "dev-ubuntu-desktop" "firefox" "firefox"

    log "Checking dev tools..."
    assert_cmd "dev-ubuntu-desktop" "node" "node"
    assert_cmd "dev-ubuntu-desktop" "npm" "npm"
    assert_cmd "dev-ubuntu-desktop" "python3" "python3"
    assert_cmd "dev-ubuntu-desktop" "git" "git"
    assert_cmd "dev-ubuntu-desktop" "gcc" "gcc"
    assert_cmd "dev-ubuntu-desktop" "vim" "vim"

    log "Checking CLI tools..."
    assert_cmd "dev-ubuntu-desktop" "curl" "curl"
    assert_cmd "dev-ubuntu-desktop" "wget" "wget"
    assert_cmd "dev-ubuntu-desktop" "htop" "htop"
    assert_cmd "dev-ubuntu-desktop" "tmux" "tmux"
    assert_cmd "dev-ubuntu-desktop" "jq" "jq"
    assert_cmd "dev-ubuntu-desktop" "rg" "ripgrep"

    log "Checking ports..."
    assert_port "dev-ubuntu-desktop" "22"
    assert_port "dev-ubuntu-desktop" "5900"
fi

########################################
# LAYER 3: AGENTS
########################################

header "━━━ Layer 3: claude-code ━━━"
if assert_image_exists "claude-code"; then
    assert_label "claude-code" "ai.proxifai.image.layer" "3"
    assert_label "claude-code" "ai.proxifai.base-tool" "claude-code"

    log "Checking dev-node inheritance..."
    assert_cmd "claude-code" "node" "node (from dev-node)"
    assert_cmd "claude-code" "npm" "npm (from dev-node)"
    assert_cmd "claude-code" "pnpm" "pnpm (from dev-node)"
    assert_cmd "claude-code" "tsc" "typescript (from dev-node)"
    assert_cmd "claude-code" "nvim" "neovim (from base)"
    assert_cmd "claude-code" "rg" "ripgrep (from base)"

    log "Checking Claude Code CLI..."
    assert_cmd "claude-code" "claude" "claude-code CLI"
fi

header "━━━ Layer 3: gemini-cli ━━━"
if assert_image_exists "gemini-cli"; then
    assert_label "gemini-cli" "ai.proxifai.image.layer" "3"

    log "Checking dev-node inheritance..."
    assert_cmd "gemini-cli" "node" "node (from dev-node)"
    assert_cmd "gemini-cli" "pnpm" "pnpm (from dev-node)"
    assert_cmd "gemini-cli" "nvim" "neovim (from base)"

    log "Checking Gemini CLI..."
    # Gemini CLI package name may vary - check for the binary
    assert_cmd "gemini-cli" "gemini" "gemini CLI" || skip "gemini CLI (package may not be available)"
fi

header "━━━ Layer 3: copilot ━━━"
if assert_image_exists "copilot"; then
    assert_label "copilot" "ai.proxifai.image.layer" "3"

    log "Checking dev-node inheritance..."
    assert_cmd "copilot" "node" "node (from dev-node)"
    assert_cmd "copilot" "pnpm" "pnpm (from dev-node)"
    assert_cmd "copilot" "nvim" "neovim (from base)"

    log "Checking GitHub CLI..."
    assert_cmd "copilot" "gh" "github-cli (gh)"
fi

header "━━━ Layer 3: aider ━━━"
if assert_image_exists "aider"; then
    assert_label "aider" "ai.proxifai.image.layer" "3"

    log "Checking dev-python inheritance..."
    assert_cmd "aider" "python3" "python3 (from dev-python)"
    assert_cmd "aider" "pip" "pip (from dev-python)"
    assert_cmd "aider" "poetry" "poetry (from dev-python)"
    assert_cmd "aider" "nvim" "neovim (from base)"

    log "Checking Aider..."
    assert_cmd "aider" "aider" "aider CLI"
fi

header "━━━ Layer 3: cursor ━━━"
if assert_image_exists "cursor"; then
    assert_label "cursor" "ai.proxifai.image.layer" "3"

    log "Checking dev-fullstack inheritance..."
    assert_cmd "cursor" "node" "node (from dev-fullstack)"
    assert_cmd "cursor" "python3" "python3 (from dev-fullstack)"
    assert_cmd "cursor" "docker" "docker-cli (from dev-fullstack)"
    assert_cmd "cursor" "gcc" "gcc (from dev-fullstack)"
    assert_cmd "cursor" "nvim" "neovim (from base)"
    assert_cmd "cursor" "tmux" "tmux (from base)"
fi

header "━━━ Layer 3: opencode ━━━"
if assert_image_exists "opencode"; then
    assert_label "opencode" "ai.proxifai.image.layer" "3"

    log "Checking dev-go inheritance..."
    assert_cmd "opencode" "go" "go (from dev-go)"
    assert_cmd "opencode" "golangci-lint" "golangci-lint (from dev-go)"
    assert_cmd "opencode" "nvim" "neovim (from base)"

    log "Checking OpenCode tools..."
    assert_cmd "opencode" "ttyd" "ttyd"
    assert_port "opencode" "3000"
fi

########################################
# CROSS-CUTTING TESTS
########################################

header "━━━ Cross-cutting: SSH works in all images ━━━"
for img in base dev-node dev-python dev-go dev-rust dev-fullstack dev-desktop dev-ubuntu-desktop claude-code gemini-cli copilot aider cursor opencode; do
    if docker image inspect "${REGISTRY}/${img}:${TAG}" >/dev/null 2>&1; then
        assert_cmd "$img" "sshd" "sshd in ${img}"
    fi
done

header "━━━ Cross-cutting: /workspace exists in all images ━━━"
for img in base dev-node dev-python dev-go dev-rust dev-fullstack dev-desktop dev-ubuntu-desktop claude-code gemini-cli copilot aider cursor opencode; do
    if docker image inspect "${REGISTRY}/${img}:${TAG}" >/dev/null 2>&1; then
        assert_workdir "$img" "/workspace"
    fi
done

########################################
# SUMMARY
########################################
echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}  Test Results${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed: ${PASS}${NC}"
echo -e "  ${RED}Failed: ${FAIL}${NC}"
echo -e "  ${YELLOW}Skipped: ${SKIP}${NC}"
echo ""

if [ ${FAIL} -gt 0 ]; then
    echo -e "${RED}${BOLD}FAILURES:${NC}"
    for e in "${ERRORS[@]}"; do
        echo -e "  ${RED}✗${NC} ${e}"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    exit 0
fi
