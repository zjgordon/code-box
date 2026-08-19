# Isolated Docker sandbox (Sysbox DinD)

Sibling Docker Engine for agents in `code-box`, without the host socket.

## Architecture

`sandbox-dind` runs `dockerd` under `sysbox-runc` on `sandbox-net`. `code-box` reaches it over TCP + TLS (`DOCKER_HOST=tcp://sandbox-dind:2376`). Nested storage is a DinD volume.

```
Host Docker (sysbox-runc)
  ├── code-box          — desktop; Docker CLI only
  └── sandbox-dind      — sandboxed dockerd (Sysbox)
         shared network: sandbox-net (egress for registry pulls)
```

Agents talk to this daemon only. Keep Traefik, Gitea, and other lab stacks off `sandbox-net`. The network has egress so pulls and builds work. Further hardening (firewall, HTTP proxy, private registry) is host policy.

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

Default `docker compose up` does not use the sibling. Nested builds share host RAM; default limit is 8G (`SANDBOX_DIND_MEMORY_LIMIT` from the repo root).

## Inside the desktop

`docker` / `docker compose` target the sandboxed daemon: build and run stacks under `/workspace`, iterate, tear down. Registry pulls use `sandbox-net` egress.

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
| `network sandbox-net declared as external, but could not be found` | Start `sandbox-dind` before the overlay. |
| `error during connect` / TLS errors | Regenerate certs; `./certs/client` mounted; `DOCKER_CERT_PATH=/certs/client`. |
| Registry DNS / pull failures | Recreate `sandbox-net` (`docker compose -f sandbox-dind/docker-compose.yaml down` then `up -d`). |
| `unknown or invalid runtime name: sysbox-runc` | [Package install](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md); `docker info` lists `sysbox-runc`. |
| `docker: command not found` in desktop | Rebuild `code-box`. |
| Cert CA already exists | Re-run is a no-op; `FORCE=1` replaces the CA and leaves. |
