# Isolated Docker sandbox (Sysbox DinD)

Optional sibling Docker Engine for agents inside `code-box`, without mounting the host Docker socket.

## Architecture

A **sibling** container (`sandbox-dind`) runs `dockerd` under the **Sysbox** runtime (`sysbox-runc`) on a **dedicated** bridge network (`sandbox-net`). `code-box` attaches to that network and talks to the daemon over **TCP + TLS** (`DOCKER_HOST=tcp://sandbox-dind:2376`). Nested container storage lives in a DinD volume, not on the host engine.

```
Host Docker (sysbox-runc)
  ├── code-box          — desktop; Docker CLI only
  └── sandbox-dind      — sandboxed dockerd (Sysbox)
         shared network: sandbox-net (egress allowed for registry pulls)
```

**Isolation model:** agents talk only to the sandboxed daemon (not the host Docker socket). `sandbox-net` is a separate Compose network — keep Traefik, Gitea, and other lab stacks off it. The network allows outbound egress so `docker pull` / builds that fetch base images work; it is intentionally **not** `internal: true` (that mode blocks DNS and Hub access, which breaks normal agent workflows).

Hardening beyond this (firewall rules, HTTP proxy, private registry only) is host/operator policy.

## Host requirements (operator-owned)

This repo does **not** install Sysbox. You install it on the **host** that runs Docker before bringing up `sandbox-dind`.

Upstream guide (start here): [Sysbox User Guide: Installation with the Sysbox Package](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md). Packages are published on the [Sysbox releases](https://github.com/nestybox/sysbox/releases) page (Ubuntu/Debian `.deb` builds). Distro/kernel compatibility: [distro-compat](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md).

### What Sysbox is in this setup

`sandbox-dind` sets `runtime: sysbox-runc`. That tells the **host** Docker engine to start the DinD container with Sysbox instead of plain `runc`. Sysbox is installed at the host level (like another OCI runtime); it is not something you put inside the `code-box` image.

### Install checklist

1. Supported Linux distro with **systemd**, and Docker installed **natively** (not the Snap package — Sysbox does not support Snap Docker; see the upstream guide).
2. Download a Sysbox CE `.deb` from [releases](https://github.com/nestybox/sysbox/releases) (example for current CE amd64; replace with the version/arch you need):

   ```bash
   wget https://downloads.nestybox.com/sysbox/releases/v0.7.1/sysbox-ce_0.7.1-0.linux_amd64.deb
   # verify checksum against the release notes, then:
   sudo apt-get update
   sudo apt-get install -y jq
   sudo apt-get install ./sysbox-ce_0.7.1-0.linux_amd64.deb
   ```

   The installer may reconfigure/restart Docker so it learns about `sysbox-runc`. On a busy host, read upstream’s notes on installing without restarting Docker and on stopping containers first.

3. Confirm Sysbox is running and Docker sees the runtime:

   ```bash
   systemctl status sysbox -n20
   docker info | grep -i runtime
   # expect: Runtimes: ... sysbox-runc
   ```

4. Optional on older kernels: [shiftfs / ID-mapped mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md#installing-shiftfs-for-linux-kernels--63) (kernels ≥ 6.3 use ID-mapped mounts; shiftfs is mainly for older kernels).

Gotchas: storage-driver or volume-plugin combos can cause trouble — run `docker info` and read upstream troubleshooting before using this on a critical host. Do **not** set Sysbox as Docker’s default runtime unless you intend every container to use it; this project only needs `runtime: sysbox-runc` on `sandbox-dind`.


## Prerequisites in this repo

1. Generate TLS material (private CA + server + client):

   ```bash
   ./scripts/generate-dind-certs.sh
   ```

   PEMs under `certs/` are gitignored. Set `FORCE=1` to rotate.

2. Rebuild `code-box` so the image includes the Docker CLI (if you have not built since this feature landed):

   ```bash
   docker compose build
   ```

## Bring-up order

Start the sibling first (creates network `sandbox-net`), then `code-box` with the sandbox overlay:

```bash
docker compose -f sandbox-dind/docker-compose.yaml up -d
docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml up -d
```

Default `docker compose up` (no overlay) is unchanged and does not require the sibling network.

Nested builds compete with the desktop for host RAM: `sandbox-dind` defaults to an **8G** memory limit (`SANDBOX_DIND_MEMORY_LIMIT` in `.env` when compose is run from the repo root). Raise it if large nested builds OOM.

## Inside the desktop

With the overlay active, `docker` / `docker compose` target the sandboxed daemon:

- Build images and run compose stacks for projects under `/workspace`
- Smoke-test services the agent starts
- Tear down and iterate

They do **not**:

- Touch the host Docker socket or host containers managed by the host engine
- Escape Sysbox’s user-namespace model to host root via nested `--privileged` in the usual way Sysbox is designed to prevent

They **can** pull from public registries over `sandbox-net` egress (required for normal `docker run` / builds). Do not attach lab services you want unreachable (Traefik, Gitea, etc.) to `sandbox-net`.

## Files

| Path | Role |
|------|------|
| [`sandbox-dind/docker-compose.yaml`](../sandbox-dind/docker-compose.yaml) | DinD sibling (`runtime: sysbox-runc`, dedicated net, TLS) |
| [`docker-compose.sandbox.yaml`](../docker-compose.sandbox.yaml) | Overlay: `DOCKER_*` + client certs + `sandbox-net` |
| [`scripts/generate-dind-certs.sh`](../scripts/generate-dind-certs.sh) | One-shot cert generation |
| [`certs/`](../certs/) | Generated PEMs (not committed) |

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `network sandbox-net declared as external, but could not be found` | Start `sandbox-dind` before the overlay compose. |
| `error during connect` / TLS errors | Regenerate certs; confirm `./certs/client` is mounted and `DOCKER_CERT_PATH=/certs/client`. |
| `lookup registry-1.docker.io ... server misbehaving` / pull failures | Recreate `sandbox-net` after pulling this change (egress must be allowed — see Architecture). Old stacks created with `internal: true` need `docker compose -f sandbox-dind/docker-compose.yaml down` then `up -d` (or remove the old `sandbox-net` network). |
| `unknown or invalid runtime name: sysbox-runc` | Install Sysbox on the host per the [package install guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md); confirm `docker info` lists `sysbox-runc`. |
| `docker: command not found` in desktop | Rebuild the `code-box` image after pulling Dockerfile changes. |
| Cert CA already exists warning | Expected on re-run; use `FORCE=1` to replace the CA and all leaf certs. |
