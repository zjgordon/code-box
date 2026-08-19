# Ollama (local model host)

Optional sibling [Ollama](https://ollama.com) for OpenCode. Default `docker compose up` does not start it.

## Architecture

Ollama is on the default Compose network. From the desktop: `http://ollama:11434` (OpenAI-compatible `http://ollama:11434/v1`). Models live in a named volume. Host bind is `127.0.0.1:11434`. Leave Ollama off `sandbox-net`; `code-box` reaches it on the default network when both overlays are up.

```
Host Docker
  ├── code-box     — desktop; OpenCode at http://ollama:11434/v1
  └── ollama       — model host (CPU, or NVIDIA via extra overlay)
         shared network: default Compose network
         host bind: 127.0.0.1:11434
```

The base overlay is CPU. `docker-compose.ollama.gpu.yaml` adds NVIDIA device reservations.

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

`code-box` waits until Ollama is healthy. Default memory limit is 8G (`OLLAMA_MEMORY_LIMIT`). Pin `OLLAMA_VERSION` or `OLLAMA_HOST_PORT` in `.env`. If the host already binds 11434, set `OLLAMA_HOST_PORT` to a free loopback port; Compose DNS remains `ollama:11434`.

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

If the TUI asks for a key: `/connect` → Other → provider id `ollama` → any non-empty string.

Upstream: [OpenCode providers](https://opencode.ai/docs/providers/), [Ollama ↔ OpenCode](https://docs.ollama.com/integrations/opencode).

## Files

| Path | Role |
|------|------|
| [`docker-compose.ollama.yaml`](../docker-compose.ollama.yaml) | Overlay: Ollama sibling + healthcheck + loopback port |
| [`docker-compose.ollama.gpu.yaml`](../docker-compose.ollama.gpu.yaml) | Overlay: NVIDIA GPU reservations |
| [`data/workspace/opencode.json.example`](../data/workspace/opencode.json.example) | OpenCode provider stub (`http://ollama:11434/v1`) |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `could not select device driver nvidia` | Toolkit on the host; GPU overlay only with NVIDIA. |
| Connection refused | Overlay in the `-f` list; `docker exec ollama ollama list`; OpenCode `baseURL` `http://ollama:11434/v1`. |
| Model missing from the OpenCode picker | Exact `ollama list` tag under `provider.ollama.models`; restart the TUI. |
| OOM / container killed | Raise `OLLAMA_MEMORY_LIMIT` or use a smaller model. |
| `curl: (7) Failed to connect` from the host | Loopback only: `http://127.0.0.1:11434` (or `OLLAMA_HOST_PORT`), or `docker exec`. |
| `failed to bind host port 127.0.0.1:11434` | Set `OLLAMA_HOST_PORT` or stop the host unit. Desktop still uses `http://ollama:11434/v1`. |
