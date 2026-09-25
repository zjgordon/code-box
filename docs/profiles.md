# Operating Profiles

Profiles name the intended security posture of a code-box session. They do not claim controls that have not been implemented yet.

| Profile | Command | Docker | Credentials and egress |
|---------|---------|--------|------------------------|
| **Local functional development** | `scripts/up.sh` or `scripts/up.sh --profile local-functional` | No Docker daemon in the desktop | Full `/config` state and broad egress remain available to the desktop agent |
| **Contained build execution** | `scripts/up.sh --profile contained-build` | Sysbox DinD sibling over mutual TLS | `/config` is absent from DinD and nested containers; `/workspace` is shared read-write; broad egress remains available |
| **Protected agent operation** | `scripts/up.sh --profile protected-agent [--egress-proxy]` | Optional Sysbox DinD with `--sandbox` | Separate `./data/config-protected` state; read-only GitHub MCP defaults; proxy/firewall egress policy is opt-in |

`scripts/up.sh --sandbox` remains a compatibility alias for `--profile contained-build`. New documentation and automation should use the profile name.

## Local Functional Development

This is the default profile. It is intended for a trusted human-operated workstation and prioritizes an unrestricted desktop workflow. It has no Docker daemon inside the desktop, no host Docker socket, Docker's default seccomp profile, loopback-only KasmVNC, and the resource limits described in the [threat model](threat-model.md).

The agent can read the operator's `/config` state and has broad network access. Do not use this profile as a credential-isolation boundary.

## Contained Build Execution

This profile starts the Sysbox DinD sibling and configures the desktop Docker CLI to use it over mutual TLS. It is the profile to use when an agent needs to build or run project containers.

Nested containers receive `/workspace`, but never `/config` or the host Docker socket. They can modify the shared workspace and have broad egress for registry pulls and package installation. This is a build containment boundary, not a protected-agent credential profile.

## Protected Agent Operation

This profile replaces the operator's full `./data/config` mount with `./data/config-protected`, created with mode `0700` by `scripts/up.sh`. Provision only credentials an agent is allowed to read. A normal desktop login, full GitHub token, SSH keys, and provider OAuth state are not copied automatically.

```bash
scripts/up.sh --profile protected-agent
# Add --sandbox only when the agent needs contained Docker builds.
```

GitHub MCP defaults to `GITHUB_READ_ONLY=1` and `GITHUB_TOOLSETS=default`, excluding Actions. Use a fine-grained, read-only GitHub token in the protected state. The `gh` CLI has the same token access as the profile state, so token scopes remain the actual authorization boundary.

Without `--egress-proxy`, the profile still has broad egress. With it, the host-managed proxy and root firewall policy restrict forwarded external traffic. A prompt-injected agent can exfiltrate any credential placed in `./data/config-protected` to an allowlisted destination, and it can still reach host-local services until WG-08. See [egress-proxy.md](egress-proxy.md) and [walled-garden-hardening-plan.md](walled-garden-hardening-plan.md).
