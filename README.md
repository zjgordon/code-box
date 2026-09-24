# code-box

[![Docker](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)](./docker-compose.yaml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](./LICENSE)
[![Release](https://img.shields.io/github/v/release/zjgordon/code-box)](https://github.com/zjgordon/code-box/releases)

Wanted to play with all the fun stuff in as much of a walled garden as possible. Full dev box in a browser (**XFCE** + **KasmVNC**) with **Cursor**, **VS Code**, **Claude Code**, and **OpenCode**, plus an opt-in **walled-garden mode** that gives agents an **isolated Docker** daemon (Sysbox sibling, never the host socket). Optional **Ollama** container to host a local LLM for **OpenCode**. Run it locally over HTTP and open projects in `/workspace`.

What the wall holds and what it deliberately leaves open: [docs/threat-model.md](docs/threat-model.md).

![code-box desktop](docs/img/code-box-screenshot.jpg)

## Requirements

- Docker Engine with Compose v2

Isolated Docker requires [Sysbox](docs/sandbox-docker.md) on the host. Ollama GPU requires NVIDIA drivers and the [Container Toolkit](docs/ollama.md).

## Quick start

```bash
cp .env.example .env   # set CODE_BOX_USER and CODE_BOX_PASSWORD (required)
```

**Dev box (default).** Desktop and agents, no Docker inside the desktop, no host socket:

```bash
scripts/up.sh --build        # or: docker compose build && docker compose up -d
```

**Walled garden.** Same desktop, and agents get their own Docker daemon (Sysbox DinD over TLS). Install [Sysbox](docs/sandbox-docker.md#host-requirements) on the host first. The script checks for `sysbox-runc`, generates TLS certs, starts `sandbox-dind`, waits for it to be healthy, and then starts the desktop:

```bash
scripts/up.sh --sandbox --build
```

Add `--ollama` (and `--gpu`) for the local-model sibling; `--down` stops the same set.

Open [http://localhost:3000](http://localhost:3000) (or `http://<host-ip>:3000` on a trusted LAN; see [Security](#security)), sign in, then run `claude login` in a desktop terminal. For OpenCode, use `/connect` in the TUI to configure an LLM provider. To clone and manage GitHub repos over SSH (MFA-compatible), see [docs/github.md](docs/github.md). Agents use Playwright, GitHub, and Fetch MCP; see [docs/mcp.md](docs/mcp.md) (Playwright details: [docs/browser.md](docs/browser.md)). For other layouts (LAN reverse proxy, HTTPS on a personal server), see [docs/deployment_examples.md](docs/deployment_examples.md).

Optional: set `CODE_BOX_PORT` in `.env` if host port `3000` is taken.

Resources (defaults work for agent/desktop use; override in `.env`): `CODE_BOX_MEMORY_LIMIT` (16G), `CODE_BOX_CPUS` (8.0), `CODE_BOX_SHM_SIZE` (1gb).

## Security

"Walled garden" is scoped, not absolute. Neither mode gives agents the host Docker socket. Sandbox mode keeps credentials (`/config`) out of the Docker daemon agents use, and keeps lab services off its network. Egress is open, the GitHub MCP uses your full `gh` token, and the desktop runs with `seccomp=unconfined`. KasmVNC is **plain HTTP on all interfaces**: fine on your own workstation, but anywhere else put an HTTPS reverse proxy in front ([deployment examples](docs/deployment_examples.md)). Full list and hardening checklist: [docs/threat-model.md](docs/threat-model.md).

## Optional: GitHub

To clone, review, and manage public GitHub repositories from the desktop (`gh`, SSH, MFA, Verified commits), see [docs/github.md](docs/github.md).

## Agent MCP tools

Agents in Cursor, Claude Code, and OpenCode share Playwright (browser), GitHub (API + Actions), and Fetch (HTTP → markdown). See [docs/mcp.md](docs/mcp.md). Playwright details: [docs/browser.md](docs/browser.md).

## Walled garden: isolated Docker

The walled-garden mode: `scripts/up.sh --sandbox`. The desktop gets a sandboxed Docker Engine (Sysbox sibling DinD, not the host socket). Manual steps and troubleshooting: [docs/sandbox-docker.md](docs/sandbox-docker.md).

## Optional: Ollama

To host a local model for OpenCode (optional sibling container; NVIDIA GPU is a second overlay): `scripts/up.sh --ollama [--gpu] [--sandbox]`. See [docs/ollama.md](docs/ollama.md).

## Versioning

- **Releases:** git tags `vMAJOR.MINOR.PATCH` (see [Releases](../../releases))
- **Image tag:** `local/code-box:<CURSOR_VERSION>` (default `3.14`)
- **Build pins** (override in `.env`): `CURSOR_VERSION`, `NODE_VERSION`, `NVM_VERSION`, `CLAUDE_CODE_VERSION`, `OPENCODE_VERSION`, `PLAYWRIGHT_MCP_VERSION`, `GITHUB_MCP_VERSION`, `FETCH_MCP_VERSION`

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
