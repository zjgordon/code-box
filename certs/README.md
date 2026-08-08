# TLS certificates (sandbox DinD)

Private CA, server, and client PEMs for `sandbox-dind` ↔ `code-box` Docker TLS.

**Do not commit `*.pem` files.** Generate on the host:

```bash
./scripts/generate-dind-certs.sh
```

Set `FORCE=1` to regenerate the CA and all certs. See [docs/sandbox-docker.md](../docs/sandbox-docker.md).
