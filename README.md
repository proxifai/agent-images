# ProxifAI Agent Images

Minimal Docker base images for ProxifAI agents. All images are built on Alpine Linux for minimal size and fast container startup.

## Available Images

| Image | Size | Base Tool | Description |
|-------|------|-----------|-------------|
| `base` | ~15MB | - | Minimal Alpine with SSH, bash, curl, git |
| `claude-code` | ~80MB | claude-code | Node.js for Claude Code CLI |
| `cursor` | ~200MB | cursor | Full dev environment (Node.js, Python, GCC) |
| `opencode` | ~300MB | opencode | Go with web terminal (ttyd) support |
| `gemini-cli` | ~80MB | gemini-cli | Node.js for Google Gemini CLI |
| `copilot` | ~100MB | copilot | Node.js with GitHub CLI |
| `aider` | ~120MB | aider | Python for Aider AI pair programming |

## Usage

Pull an image:
```bash
docker pull ghcr.io/proxifai/agent-images/claude-code:latest
```

Run a container:
```bash
docker run -d -p 2222:22 ghcr.io/proxifai/agent-images/claude-code:latest
```

SSH into the container:
```bash
ssh root@localhost -p 2222
# Password: root
```

## Manifest

The `manifest.json` file contains metadata about all available images. ProxifAI fetches this to display available images when creating agents.

Manifest URL: `https://raw.githubusercontent.com/proxifai/agent-images/main/manifest.json`

## Building Images Locally

```bash
# Build base image
docker build -t proxifai/base:latest images/base/

# Build a specific tool image
docker build -t proxifai/claude-code:latest images/claude-code/
```

## Contributing

1. Create a new directory under `images/`
2. Add a `Dockerfile` with appropriate labels
3. Update `manifest.json` with the new image metadata
4. Submit a pull request

## Labels

All images include these OCI labels:
- `org.opencontainers.image.title` - Image title
- `org.opencontainers.image.description` - Description
- `ai.proxifai.image.type` - Image type (base, claude-code, etc.)
- `ai.proxifai.image.version` - Version string
- `ai.proxifai.base-tool` - Associated base tool (if any)

## License

MIT License - see LICENSE file for details.
