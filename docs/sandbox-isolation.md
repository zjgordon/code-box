# Sandbox-to-Desktop Isolation

`sandbox-dind` and code-box share `sandbox-net` so the desktop Docker CLI can reach the sibling daemon over TLS. Docker bridge networks are bidirectional, which also lets workloads launched by DinD initiate connections to services listening in code-box.

`scripts/apply-sandbox-isolation.sh` installs a root-only stateful firewall rule that drops new `sandbox-dind` to code-box connections. It permits established replies, so code-box can continue to control dockerd at `sandbox-dind:2376`.

## Apply

Start the contained-build or protected-agent profile with `--sandbox`, then apply the rule while both containers are running:

```bash
sudo ./scripts/apply-sandbox-isolation.sh
```

The script resolves current `sandbox-net` addresses for `code-box` and `sandbox-dind`. Reapply after either container or the network is recreated.

## Verify

From code-box, the Docker daemon must remain reachable:

```bash
docker info
```

From a disposable nested container, a new connection to code-box's sandbox address and port 3000 must fail. The exact test address can be read with:

```bash
docker inspect code-box --format '{{with index .NetworkSettings.Networks "sandbox-net"}}{{.IPAddress}}{{end}}'
docker network inspect sandbox-net
```

Use the `sandbox-net` address shown for `code-box`, then run a nested container with an HTTP client to that address. Existing established connections are intentionally allowed.

## Remove

Remove the rule before tearing down either container, while their current addresses are still known:

```bash
sudo ./scripts/apply-sandbox-isolation.sh --remove
```

This policy blocks only the DinD source identity to code-box on `sandbox-net`. It does not replace the egress policy in [egress-proxy.md](egress-proxy.md), and it does not protect services on other Docker networks.
