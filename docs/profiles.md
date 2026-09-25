# Operating Profiles

Profiles name the intended security posture of a code-box session. They do not claim controls that have not been implemented yet.

| Profile | Command | Docker | Credentials and egress |
|---------|---------|--------|------------------------|
| **Local functional development** | `scripts/up.sh` or `scripts/up.sh --profile local-functional` | No Docker daemon in the desktop | Full `/config` state and broad egress remain available to the desktop agent |
| **Contained build execution** | `scripts/up.sh --profile contained-build` | Sysbox DinD sibling over mutual TLS | `/config` is absent from DinD and nested containers; `/workspace` is shared read-write; broad egress remains available |
| **Protected agent operation** | Not available yet | Not available yet | Blocked until credential scoping and egress policy are implemented in WG-06 and WG-07 |

`scripts/up.sh --sandbox` remains a compatibility alias for `--profile contained-build`. New documentation and automation should use the profile name.

## Local Functional Development

This is the default profile. It is intended for a trusted human-operated workstation and prioritizes an unrestricted desktop workflow. It has no Docker daemon inside the desktop, no host Docker socket, Docker's default seccomp profile, loopback-only KasmVNC, and the resource limits described in the [threat model](threat-model.md).

The agent can read the operator's `/config` state and has broad network access. Do not use this profile as a credential-isolation boundary.

## Contained Build Execution

This profile starts the Sysbox DinD sibling and configures the desktop Docker CLI to use it over mutual TLS. It is the profile to use when an agent needs to build or run project containers.

Nested containers receive `/workspace`, but never `/config` or the host Docker socket. They can modify the shared workspace and have broad egress for registry pulls and package installation. This is a build containment boundary, not a protected-agent credential profile.

## Protected Agent Operation

This profile is deliberately unavailable. Enabling it before separate credential handling and egress enforcement exist would create a misleading security claim. `scripts/up.sh --profile protected-agent` fails without starting or stopping any services.

See [walled-garden-hardening-plan.md](walled-garden-hardening-plan.md) for the remaining prerequisites.
