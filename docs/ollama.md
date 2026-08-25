# Ollama (local model host)

Optional sibling [Ollama](https://ollama.com) for OpenCode. Default `docker compose up` does not start it.

## Architecture

Ollama and `code-box` share a dedicated Compose network `ollama-net`. From the desktop: `http://ollama:11434` (OpenAI-compatible `http://ollama:11434/v1`). A loopback proxy also serves `http://127.0.0.1:11434` inside `code-box` so OpenCode’s default discovery works. Models live in a named volume. Host bind is `127.0.0.1:11434`. Leave Ollama off `sandbox-net`; `code-box` reaches it on `ollama-net` when both overlays are up.

```
Host Docker
  ├── code-box                 — desktop; OpenCode at http://ollama:11434/v1
  │     └── ollama-localhost-proxy  — 127.0.0.1:11434 → ollama:11434
  └── ollama                   — model host (CPU, or NVIDIA via extra overlay)
         shared network: ollama-net
         host bind: 127.0.0.1:11434
```

The base overlay is CPU. `docker-compose.ollama.gpu.yaml` adds NVIDIA device reservations.

Apply every overlay you need in **one** `docker compose` invocation (same project). A separate `docker run --name ollama` or a second Compose project will not join `ollama-net`, and `http://ollama:11434` will fail from the desktop.

## Host requirements

CPU: Docker Engine with Compose v2.

GPU: NVIDIA drivers and [Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host. See also [Ollama Docker](https://docs.ollama.com/docker).

`docker-compose.ollama.gpu.yaml` sets `deploy.resources.reservations.devices` (`driver: nvidia`, `capabilities: [gpu]`).

### NVIDIA checklist

1. `nvidia-smi` on the host.
2. Install the toolkit (Debian/Ubuntu; use upstream for other distros):

   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
     | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   ```

3. Wire Docker and restart:

   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```

4. Confirm GPU in a container:

   ```bash
   docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
   ```

Without the toolkit, the GPU overlay fails with `could not select device driver nvidia`. AMD/ROCm: [Ollama Docker](https://docs.ollama.com/docker) (`ollama/ollama:rocm`).

## Bring-up

CPU:

```bash
docker compose -f docker-compose.yaml -f docker-compose.ollama.yaml up -d
```

NVIDIA GPU:

```bash
docker compose -f docker-compose.yaml -f docker-compose.ollama.yaml -f docker-compose.ollama.gpu.yaml up -d
```

With sandbox (start `sandbox-dind` first; [sandbox-docker.md](sandbox-docker.md)):

```bash
docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml -f docker-compose.ollama.yaml up -d
```

Sandbox + NVIDIA GPU (all overlays in one project):

```bash
docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml -f docker-compose.ollama.yaml -f docker-compose.ollama.gpu.yaml up -d
```

To make that the default for `docker compose up`, set `COMPOSE_FILE` in `.env` (see `.env.example`).

`code-box` waits until Ollama is healthy. Default memory limit is 8G (`OLLAMA_MEMORY_LIMIT`). Pin `OLLAMA_VERSION` or `OLLAMA_HOST_PORT` in `.env`. If the host already binds 11434, set `OLLAMA_HOST_PORT` to a free loopback port; Compose DNS remains `ollama:11434`.

From inside `code-box`, both of these should list models:

```bash
curl -sS http://ollama:11434/api/tags
curl -sS http://127.0.0.1:11434/api/tags
```

## Acquire a model

```bash
docker exec -it ollama ollama pull qwen2.5-coder
docker exec -it ollama ollama list
```

Library: [ollama.com/library](https://ollama.com/library). `qwen2.5-coder` is a typical OpenCode host on GPU. `smollm:135m` is a CPU smoke test. Host debug: `http://127.0.0.1:11434` (or `OLLAMA_HOST_PORT`).

## Configure OpenCode

OpenCode lists models from config, not discovery. Copy the example and set keys to `ollama list` tags. Global config is `/config/.config/opencode/opencode.json` (`HOME=/config`; host path `./data/config/.config/opencode/opencode.json`):

```bash
mkdir -p /config/.config/opencode
cp /workspace/opencode.json.example /config/.config/opencode/opencode.json
```

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (code-box)",
      "options": {
        "baseURL": "http://ollama:11434/v1"
      },
      "models": {
        "qwen2.5-coder:latest": {
          "name": "Qwen 2.5 Coder"
        }
      }
    }
  }
}
```

`http://ollama:11434/v1` is the Compose DNS URL. The loopback proxy also makes the stock `http://localhost:11434/v1` work from the desktop.

If the TUI asks for a key: `/connect` → Other → provider id `ollama` → any non-empty string.

Upstream: [OpenCode providers](https://opencode.ai/docs/providers/), [Ollama ↔ OpenCode](https://docs.ollama.com/integrations/opencode).

## Files

| Path | Role |
|------|------|
| [`docker-compose.ollama.yaml`](../docker-compose.ollama.yaml) | Overlay: Ollama sibling, `ollama-net`, loopback proxy, healthcheck, host loopback port |
| [`docker-compose.ollama.gpu.yaml`](../docker-compose.ollama.gpu.yaml) | Overlay: NVIDIA GPU reservations |
| [`data/workspace/opencode.json.example`](../data/workspace/opencode.json.example) | OpenCode provider stub (`http://ollama:11434/v1`) |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `could not select device driver nvidia` | Toolkit on the host; GPU overlay only with NVIDIA. |
| Connection refused / no API from the desktop | All overlays in **one** `docker compose -f …` project (not a separate `docker run --name ollama`). `docker exec code-box getent hosts ollama`. `docker exec code-box curl -sS http://ollama:11434/api/tags`. OpenCode `baseURL` `http://ollama:11434/v1` (or `http://localhost:11434/v1` via the proxy). `docker network inspect` that `code-box` is on `ollama-net` and `ollama` is not on `sandbox-net`. |
| Model missing from the OpenCode picker | Exact `ollama list` tag under `provider.ollama.models`; restart the TUI. |
| OOM / container killed | Raise `OLLAMA_MEMORY_LIMIT` or use a smaller model. |
| `curl: (7) Failed to connect` from the host | Loopback only: `http://127.0.0.1:11434` (or `OLLAMA_HOST_PORT`), or `docker exec`. |
| `failed to bind host port 127.0.0.1:11434` | Set `OLLAMA_HOST_PORT` or stop the host unit. Desktop still uses `http://ollama:11434/v1`. |
