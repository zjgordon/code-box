# Supply Chain Updates

Code-box pins container images by immutable digest and verifies downloaded build artifacts with SHA-256. Version labels remain next to their digests for readability, but the digest or checksum is the build identity.

## Verified Inputs

| Input | Pin | Verification |
|-------|-----|--------------|
| LinuxServer KasmVNC base | `Dockerfile` image digest | Docker image digest |
| Sysbox DinD | `DIND_VERSION` and `DIND_DIGEST` | Docker image digest |
| Ollama | `OLLAMA_VERSION` and `OLLAMA_DIGEST` | Docker image digest |
| Ollama socat sidecar | Compose image digest | Docker image digest |
| nvm | `NVM_VERSION` and Dockerfile SHA-256 | Downloaded archive SHA-256 |
| Cursor | `CURSOR_VERSION` and Dockerfile SHA-256 | Downloaded Debian package SHA-256 |
| GitHub MCP server | Version and per-architecture Dockerfile SHA-256 | Downloaded release archive SHA-256 |

APT repositories are authenticated by their vendor signing keys. npm and PyPI packages are version-pinned in the Dockerfile, but remain registry-trust inputs; their lock/hash coverage is distinct from the direct binary/archive verification above.

## Update Procedure

1. Select the new version from the upstream release page and review its release notes.
2. Resolve a multi-architecture image digest with `docker buildx imagetools inspect <image:tag>`.
3. Download each direct artifact from its official release URL and calculate `sha256sum <file>`.
4. Update the version and its matching digest or checksum together. Never change only the readable tag.
5. Run `scripts/test-supply-chain.sh` and `scripts/test-containment.sh`.
6. Build the image with `docker compose build`, then validate the tools affected by the update.
7. Record the reviewed upstream URL and resulting values in the pull-request description.

## Checks

```bash
scripts/test-supply-chain.sh
scripts/test-containment.sh
docker compose build
```

`scripts/test-supply-chain.sh` proves that the same checksum helper used during image builds accepts reviewed content and rejects a tampered fixture.
