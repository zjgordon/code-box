# Ollama (local model host)

Optional sibling [Ollama](https://ollama.com) container so OpenCode inside `code-box` can use a locally hosted model. Default `docker compose up` is unchanged and does not start Ollama.

## Architecture

Ollama joins the **default** Compose network with `code-box`. The desktop reaches the API at `http://ollama:11434` (OpenAI-compatible surface at `http://ollama:11434/v1`). Models persist in a named volume, not on the host filesystem.

```
Host Docker
  ├── code-box     — desktop; OpenCode talks to http://ollama:11434/v1
  └── ollama       — model host (CPU, or NVIDIA via extra overlay)
         shared network: default Compose network
         host bind: 127.0.0.1:11434 (loopback only)
```

**GPU is optional.** The base overlay runs on CPU. NVIDIA passthrough is a second overlay so hosts without the NVIDIA Container Toolkit can still start the service.

Keep Ollama **off** `sandbox-net`. If you also enable the Sysbox DinD sibling, `code-box` stays on both networks and still reaches Ollama on the default network. Do not attach Ollama to `sandbox-net`.

`localhost:11434` **inside the desktop is wrong** — that is the `code-box` container, not Ollama. Always use the Compose hostname `ollama`.

## Host requirements (operator-owned)

CPU-only bring-up needs nothing beyond Docker Engine with Compose v2.

NVIDIA GPU bring-up is **operator-owned**. This repo does **not** install drivers or the toolkit. You install them on the **host** that runs Docker before using `docker-compose.ollama.gpu.yaml`.

Upstream guides:

- [NVIDIA Container Toolkit install](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [Ollama Docker (NVIDIA)](https://docs.ollama.com/docker)

### What the GPU overlay does

`docker-compose.ollama.gpu.yaml` adds `deploy.resources.reservations.devices` with `driver: nvidia` and `capabilities: [gpu]`. That tells the **host** Docker engine to pass GPUs into the Ollama container. It is not something you put inside the `code-box` image.

### Install checklist (NVIDIA)

1. Working NVIDIA driver on the host (`nvidia-smi` succeeds).
2. Install the NVIDIA Container Toolkit (Debian/Ubuntu sketch; follow upstream for your distro):

   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
     | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   ```

3. Configure Docker and restart the engine:

   ```bash
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```

4. Confirm a GPU is visible to containers:

   ```bash
   docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
   ```

Do **not** apply the GPU overlay on a host without this stack — Compose will fail with `could not select device driver nvidia`.

AMD/ROCm is not a first-class overlay here. See [Ollama Docker docs](https://docs.ollama.com/docker) for `ollama/ollama:rocm`.

## Bring-up

CPU (no NVIDIA toolkit):

```bash
docker compose -f docker-compose.yaml -f docker-compose.ollama.yaml up -d
```

NVIDIA GPU (after the host checklist):

```bash
docker compose -f docker-compose.yaml -f docker-compose.ollama.yaml -f docker-compose.ollama.gpu.yaml up -d
```

With the sandbox overlay as well (start `sandbox-dind` first; see [sandbox-docker.md](sandbox-docker.md)):

```bash
docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml -f docker-compose.ollama.yaml up -d
```

The overlay waits until Ollama is healthy before starting `code-box`. Ollama defaults to an **8G** memory limit (`OLLAMA_MEMORY_LIMIT` in `.env`). Raise it if large models OOM. Override `OLLAMA_VERSION` or `OLLAMA_HOST_PORT` the same way. If the host already runs Ollama (`ollama.service` on `127.0.0.1:11434`), set `OLLAMA_HOST_PORT` to a free loopback port or stop the host unit — the containers still talk on the Compose network as `ollama:11434`.

## Acquire a model

The container starts empty. Pull a tag from the [Ollama library](https://ollama.com/library):

```bash
docker exec -it ollama ollama pull qwen2.5-coder
docker exec -it ollama ollama list
```

`qwen2.5-coder` (and similar coding models) is a reasonable host for OpenCode on a GPU box. For a tiny CPU smoke test, `smollm:135m` is enough to prove the API works; it is not a useful coding model.

From the host, the API is also on loopback (`http://127.0.0.1:11434`) for debug. It is not published on the LAN.

## Configure OpenCode

OpenCode does **not** auto-discover Ollama models. Copy the example and replace `MODEL_TAG` with the exact tag from `ollama list`.

Inside the desktop, linuxserver `HOME` is `/config`, so global OpenCode config is `/config/.config/opencode/opencode.json` (host path `./data/config/.config/opencode/opencode.json`):

```bash
mkdir -p /config/.config/opencode
cp /workspace/opencode.json.example /config/.config/opencode/opencode.json
```

Example (already set to the Compose hostname — do not use `localhost`):

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

Model object keys must match `ollama list` tags exactly.

If OpenCode asks for a provider key, use `/connect` in the TUI, choose Other, provider id `ollama`, and any non-empty dummy key (Ollama does not validate local API keys).

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
| `could not select device driver nvidia` / GPU overlay fails | Install the NVIDIA Container Toolkit on the host; do not use `docker-compose.ollama.gpu.yaml` on CPU-only hosts. |
| Connection refused / OpenCode cannot reach Ollama | Use `http://ollama:11434/v1`, not `localhost`. Confirm the Ollama overlay is in the `docker compose -f` list and `docker exec ollama ollama list` works. |
| Model missing from the OpenCode picker | Add the exact `ollama list` tag under `provider.ollama.models` and restart the TUI. |
| OOM / container killed | Raise `OLLAMA_MEMORY_LIMIT`; use a smaller model; GPU overlay does not remove RAM needs for weights/context. |
| `curl: (7) Failed to connect` from the host | API is bound to `127.0.0.1` only. Use `http://127.0.0.1:11434` on the Docker host (or your `OLLAMA_HOST_PORT`), or `docker exec`. |
| `failed to bind host port 127.0.0.1:11434: address already in use` | A host Ollama (or another process) owns 11434. Set `OLLAMA_HOST_PORT` in `.env` to a free port, or stop `ollama.service`. OpenCode inside `code-box` still uses `http://ollama:11434/v1`. |
| Default `docker compose up` has no Ollama | Expected. Pass `-f docker-compose.ollama.yaml`. |
