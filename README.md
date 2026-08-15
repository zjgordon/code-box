# code-box

[![Docker](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)](./docker-compose.yaml)

Browser-accessible coding desktop (XFCE + KasmVNC) with **Cursor**, **VS Code**, **Claude Code**, and **OpenCode**. Run it locally over HTTP and open projects in `/workspace`.

## Requirements

- Docker Engine with Compose v2

## Quick start

```bash
cp .env.example .env   # set CODE_BOX_USER and CODE_BOX_PASSWORD
docker compose build && docker compose up -d
```

Open [http://localhost:3000](http://localhost:3000) (or `http://<host-ip>:3000` on your LAN), sign in, then run `claude login` in a desktop terminal. For OpenCode, use `/connect` in the TUI to configure an LLM provider.

Optional: set `CODE_BOX_PORT` in `.env` if host port `3000` is taken.

Resources (defaults work for agent/desktop use; override in `.env`): `CODE_BOX_MEMORY_LIMIT` (16G), `CODE_BOX_CPUS` (8.0), `CODE_BOX_SHM_SIZE` (1gb).

## Optional: isolated Docker

To give the desktop a sandboxed Docker Engine (Sysbox sibling DinD, not the host socket), see [docs/sandbox-docker.md](docs/sandbox-docker.md).

## Versioning

- **Releases:** git tags `vMAJOR.MINOR.PATCH` (see [Releases](../../releases))
- **Image tag:** `local/code-box:<CURSOR_VERSION>` (default `3.14`)
- **Build pins** (override in `.env`): `CURSOR_VERSION`, `NODE_VERSION`, `NVM_VERSION`, `CLAUDE_CODE_VERSION`, `OPENCODE_VERSION`

```bash
scripts/update-cursor.sh
# bump CURSOR_VERSION, then rebuild (apt/Node/extension layers stay cached):
docker compose build && docker compose up -d
```

Use `docker compose build --no-cache` only when you need a fully clean rebuild. BuildKit (Docker’s default) caches apt/npm downloads across builds.

## Data

| Host | Container |
|------|-----------|
| `./data/config` | `/config` |
| `./data/workspace` | `/workspace` |
