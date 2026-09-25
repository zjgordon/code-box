# Egress Proxy Policy

The optional egress policy combines a host-managed HTTP(S) proxy with a root-applied Docker bridge firewall. It is intended for protected-agent operation and contained builds. It is not enabled by default.

## Scope

- `--egress-proxy` configures code-box and, when selected, sandbox-dind to use an HTTP(S) proxy.
- `scripts/apply-egress-firewall.sh` permits forwarded bridge traffic only to that proxy address and port.
- The policy blocks direct forwarded internet egress. It does not block containers from reaching host-local services; that is addressed by WG-08.
- Project containers must receive proxy settings through their own environment or build configuration. The DinD daemon uses its proxy settings for registry pulls.

## Host Proxy

Run Squid or another CONNECT-capable proxy on a non-loopback address reachable from Docker bridges. Do not expose it to untrusted networks. The proxy must enforce the hostname allowlist because an IP firewall cannot safely track CDN addresses.

Example Squid policy fragment, with the bridge subnets discovered from `docker network inspect`:

```conf
http_port 192.0.2.10:3128
acl code_box src 172.18.0.0/16
acl sandbox src 172.19.0.0/16
acl allowed_domains dstdomain .github.com .githubusercontent.com .npmjs.org .pypi.org .pythonhosted.org .docker.io .docker.com
http_access allow code_box allowed_domains
http_access allow sandbox allowed_domains
http_access deny all
```

Add model-provider, source-control, package-registry, and any required Git endpoints deliberately. Do not use a catch-all `http_access allow all` rule.

## Protected Agent

1. Set `EGRESS_PROXY_URL=http://<proxy-ip>:3128` in `.env`.
2. Start the protected profile: `scripts/up.sh --profile protected-agent --egress-proxy`.
3. Apply the firewall after Docker has created the default network:

```bash
sudo ./scripts/apply-egress-firewall.sh \
  --proxy-host <proxy-ip> \
  --network code-box_default
```

## Contained Builds

1. Set both `EGRESS_PROXY_URL` and `DIND_EGRESS_PROXY_URL` in `.env`.
2. Start the profile: `scripts/up.sh --profile contained-build --egress-proxy`.
3. Apply the policy to both Docker bridges:

```bash
sudo ./scripts/apply-egress-firewall.sh \
  --proxy-host <proxy-ip> \
  --network code-box_default \
  --network sandbox-net
```

## Remove Policy

Use the same network list to remove the dedicated chain:

```bash
sudo ./scripts/apply-egress-firewall.sh \
  --network code-box_default \
  --network sandbox-net \
  --remove
```

The script requires root and `iptables`. Review the generated rules with `sudo iptables -S DOCKER-USER` before and after applying the policy. Reapply after recreating Docker networks.
