# Isolated Docker sandbox (Sysbox DinD)

Sibling Docker Engine for agents in `code-box`, without the host socket.

## Architecture

`sandbox-dind` runs `dockerd` under `sysbox-runc` on `sandbox-net`. `code-box` reaches it over TCP + TLS (`DOCKER_HOST=tcp://sandbox-dind:2376`). Nested image storage is a DinD volume. The host workspace (`./data/workspace`) is bind-mounted into **both** containers at `/workspace` so Compose bind mounts resolve on the daemon.

```
Host Docker (sysbox-runc)
  ├── code-box          — desktop; Docker CLI only
  └── sandbox-dind      — sandboxed dockerd (Sysbox)
         shared network: sandbox-net (egress for registry pulls)
         shared bind:    ./data/workspace → /workspace
```

Agents talk to this daemon only. Keep Traefik, Gitea, Ollama, and other lab stacks off `sandbox-net`. The network has egress so pulls and builds work. Further hardening (firewall, HTTP proxy, private registry) is host policy.

Do **not** mount `/config` into dind (gh tokens, SSH keys, Cursor/Claude state). Do **not** put dockerd inside `code-box` or attach the host Docker socket.

## Host requirements

Install Sysbox on the Docker host before `sandbox-dind`.

- [Sysbox package install](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md)
- [Releases](https://github.com/nestybox/sysbox/releases) (Ubuntu/Debian `.deb`)
- [Distro/kernel compatibility](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md)

`sandbox-dind` sets `runtime: sysbox-runc` on the host engine.

### Install checklist

1. Linux with systemd; native Docker (Snap is unsupported — see upstream).
2. Sysbox CE `.deb` from [releases](https://github.com/nestybox/sysbox/releases):

   ```bash
   wget https://downloads.nestybox.com/sysbox/releases/v0.7.1/sysbox-ce_0.7.1-0.linux_amd64.deb
   # verify checksum against the release notes, then:
   sudo apt-get update
   sudo apt-get install -y jq
   sudo apt-get install ./sysbox-ce_0.7.1-0.linux_amd64.deb
   ```

   The installer may reconfigure Docker. Upstream covers install without restarting Docker and stopping containers first.

3. Runtime present:

   ```bash
   systemctl status sysbox -n20
   docker info | grep -i runtime
   # Runtimes: ... sysbox-runc
   ```

4. Older kernels: [shiftfs / ID-mapped mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md#installing-shiftfs-for-linux-kernels--63) (kernels ≥ 6.3 use ID-mapped mounts).

Leave Sysbox off Docker’s default runtime; only `sandbox-dind` needs it. Check `docker info` and upstream troubleshooting for storage-driver issues.

## Prerequisites in this repo

```bash
./scripts/generate-dind-certs.sh
```

PEMs under `certs/` are gitignored. `FORCE=1` rotates the CA and leaves.

Rebuild if the image lacks the Docker CLI:

```bash
docker compose build
```

## Bring-up order

`sandbox-dind` creates `sandbox-net`, then the overlay:

```bash
docker compose -f sandbox-dind/docker-compose.yaml up -d
docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml up -d
```

Wait until dind is healthy (`docker compose -f sandbox-dind/docker-compose.yaml ps` shows `healthy`, or `docker info` succeeds inside the desktop) before the first `docker build`. First-boot overlay init can take tens of seconds.

Default `docker compose up` does not use the sibling. Nested builds share host RAM; default limit is 8G (`SANDBOX_DIND_MEMORY_LIMIT` from the repo root).

After changing dind volumes (for example adding the `/workspace` bind), recreate that stack so leftover dind-local directories under `/workspace` are hidden by the bind:

```bash
docker compose -f sandbox-dind/docker-compose.yaml up -d
```

## Inside the desktop

`docker` / `docker compose` target the sandboxed daemon: build and run stacks under `/workspace`, iterate, tear down. Registry pulls use `sandbox-net` egress.

Login shells print a one-line reminder when `DOCKER_HOST` is set.

### Bind mounts

Compose resolves relative binds on the **client** (code-box) to an absolute path, then asks the **daemon** (dind) to mount that path. Because both containers have the host workspace at `/workspace`, this works:

```yaml
volumes:
  - ../:/app                          # → /workspace/<repo> on dind
  - node_modules:/app/node_modules
```

Do not rewrite product `*:dev.yml` files to skip the bind “so the sandbox works.” Host paths such as `/opt/docker/...` are still invisible to dind; use `/workspace/...`.

Nested containers that write to a bind as root can leave root-owned files in the workspace (same as Docker on a laptop).

### Published ports

`ports:` publish on **sandbox-dind**, not the desktop loopback.

```bash
curl http://127.0.0.1:8080/           # connection refused (agent loopback)
curl http://sandbox-dind:8080/        # works while the container is up
```

Playwright MCP should open `http://sandbox-dind:<port>/`. Vite 403s unknown `Host` headers unless the product sets `server.allowedHosts` (not a sandbox bug).

### Node version

The desktop default is Node 24 (`NODE_VERSION` in `.env`). nvm is installed; use `nvm use` / `.nvmrc` for another version. Do not assume sandbox Node matches a given repo’s CI matrix.

### GitHub Actions

`gh` can open pull requests. Workflows that run only on `push` to `main` plus `pull_request` will not start from a branch push. Open a PR to exercise hosted Actions.

### npm `devdir` warning

Cursor may set `npm_config_devdir`. npm 11 warns that this key is unknown. Interactive shells unset it; agent processes that inject the var later may still warn.

## Files

| Path | Role |
|------|------|
| [`sandbox-dind/docker-compose.yaml`](../sandbox-dind/docker-compose.yaml) | DinD sibling (`runtime: sysbox-runc`, dedicated net, TLS, `/workspace` bind) |
| [`docker-compose.sandbox.yaml`](../docker-compose.sandbox.yaml) | Overlay: `DOCKER_*` + client certs + `sandbox-net` |
| [`scripts/generate-dind-certs.sh`](../scripts/generate-dind-certs.sh) | One-shot cert generation |
| [`certs/`](../certs/) | Generated PEMs (not committed) |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `network sandbox-net declared as external, but could not be found` | Start `sandbox-dind` before the overlay. |
| `error during connect` / TLS errors | Regenerate certs; `./certs/client` mounted; `DOCKER_CERT_PATH=/certs/client`. |
| `docker info` fails right after start | Wait for the healthcheck (`start_period` 30s). Retry before the first build. |
| Bind mount is empty / hides image `/app` | Recreate `sandbox-dind` so `./data/workspace` is mounted at `/workspace`. Do not use host paths in Compose. |
| `curl 127.0.0.1:<port>` connection refused | Use `http://sandbox-dind:<port>` (published on dind). |
| Registry DNS / pull failures | Recreate `sandbox-net` (`docker compose -f sandbox-dind/docker-compose.yaml down` then `up -d`). |
| `unknown or invalid runtime name: sysbox-runc` | [Package install](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md); `docker info` lists `sysbox-runc`. |
| `docker: command not found` in desktop | Rebuild `code-box`. |
| Cert CA already exists | Re-run is a no-op; `FORCE=1` replaces the CA and leaves. |
