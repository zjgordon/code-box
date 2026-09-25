# Walled Garden Hardening Plan

**Status:** active

This is the implementation tracker for the security review following the addition of [threat-model.md](threat-model.md). It breaks the work into independently reviewable commits so a security improvement does not accidentally alter the agent workflow, Docker isolation model, or supported deployment paths.

## Goal

Code-box should make the safe path the easy path while preserving an explicitly selectable functional-development mode. The project remains a single-user system and does not claim to withstand a determined container escape. It should, however, reduce the blast radius of a prompt-injected agent, malicious dependency, or exposed desktop service.

## Operating Profiles

| Profile | Intended use | Credentials | Docker | Network posture |
|---------|--------------|-------------|--------|-----------------|
| **Local functional development** | Trusted operator and agent on one workstation | Full user `/config` state is available | Optional Sysbox DinD | Broad egress, local-only desktop by default |
| **Contained build execution** | Build or test untrusted project code | No user credentials available to nested containers | Sysbox DinD only, workspace shared deliberately | Registry/package egress only where practical |
| **Protected agent operation** | Agent works with valuable credentials or sensitive code | Scoped, least-privilege credentials and MCP tools | No host socket; Sysbox DinD only when required | Local HTTPS/proxy access and explicit egress policy |

The profiles describe security outcomes, not merely Compose file combinations. Each implementation item below states which profile it improves and which existing workflow must continue to work.

## Completion Rules

- Each item is a separate commit unless implementation demonstrates that two listed items must change atomically.
- Every behavior-changing commit adds or updates an automated check before documentation is updated.
- Tests use disposable `/config` and `/workspace` directories. They must never read, modify, or expose an operator's real credentials.
- No item may add the host Docker socket to code-box or to a nested workload.
- Compatibility exceptions are opt-in, named for the control they relax, and documented in the threat model.
- Sysbox-dependent checks are optional when the test host lacks `sysbox-runc`; all other containment checks must run on a normal Docker Engine.

## Tracking

| ID | Commit-sized change | Profile | Status | Depends on |
|----|---------------------|---------|--------|------------|
| WG-00 | Add a disposable containment smoke-test harness | All | [x] | None |
| WG-01 | Make Docker's default seccomp profile the default | All | [x] | WG-00 |
| WG-02 | Bind the desktop to loopback by default | All | [x] | WG-00 |
| WG-03 | Bound process, CPU, memory, and log/resource exhaustion | All | [x] | WG-00 |
| WG-04 | Pin and verify build and runtime supply-chain inputs | All | [ ] | WG-00 |
| WG-05 | Formalize profile selection and compatibility overrides | All | [ ] | WG-01, WG-02, WG-03 |
| WG-06 | Separate and scope credentials and MCP capabilities | Protected agent operation | [ ] | WG-05 |
| WG-07 | Design and implement outbound egress controls | Contained build execution, Protected agent operation | [ ] | WG-05, WG-06 |
| WG-08 | Reduce nested-container access to code-box services | Contained build execution, Protected agent operation | [ ] | WG-07 |
| WG-09 | Reconcile documentation, examples, and release checks | All | [ ] | WG-01 through WG-08 |

## WG-00: Disposable Containment Smoke Tests

**Intent:** establish regression coverage before changing security defaults.

**Expected commit scope:** a test script or Make target, temporary test fixtures outside the repository state, and contributor documentation.

**Checks:**

- Render each supported Compose combination with `docker compose config`.
- Start code-box with disposable mounts and assert that `/proc/1/status` reports `Seccomp: 2` when no compatibility override is selected.
- Assert that KasmVNC is running and returns its expected authentication challenge.
- Assert that Cursor, VS Code, Firefox, Claude, OpenCode, and the three MCP wrappers can start or report a version/help response without accessing real credentials.
- Assert that the code-box container has no host Docker socket mount.
- When Sysbox is available, assert that the sandbox daemon uses `sysbox-runc`, publishes no host ports, and does not receive `/config`.

**Acceptance:** one command completes with cleanup on success and failure. It leaves no containers, networks, volumes, images, credentials, or changed repository files behind.

**Runner:** `scripts/test-containment.sh`. Set `CODE_BOX_TEST_IMAGE` when testing an image tag other than the default `local/code-box:3.14`. The runner performs the Sysbox DinD assertion automatically when `sysbox-runc` is installed.

## WG-01: Default Seccomp

**Intent:** restore Docker's builtin seccomp filter for normal code-box operation.

**Expected commit scope:** Compose defaults, a clearly named opt-in compatibility override, threat-model and troubleshooting updates, and WG-00 assertions.

**Implementation direction:** remove `seccomp=unconfined` from the base Compose service. Retain a separately named, explicit compatibility overlay for hosts that have a confirmed incompatibility. Do not make the compatibility exception implicit through an environment variable.

**Acceptance:** default-profile smoke tests pass on the supported Docker Engine. The desktop starts, Cursor and VS Code run, Firefox opens, and the Playwright MCP wrapper starts. The compatibility overlay changes the process status to `Seccomp: 0` and is not used by `scripts/up.sh` unless the operator explicitly selects it.

**Known observation:** the review host successfully booted the current image with `Seccomp: 2`; Firefox logged a user-namespace sandbox warning but remained running. This is a test case, not a reason to retain unconfined seccomp.

## WG-02: Local-Only Desktop Edge

**Intent:** prevent accidental exposure of KasmVNC and its password over plaintext LAN HTTP.

**Expected commit scope:** Compose port binding, environment example, deployment documentation, and WG-00 port assertions.

**Implementation direction:** bind the base desktop port to `127.0.0.1`. Provide a deliberate LAN/reverse-proxy override with clear HTTPS requirements. Do not silently make a reverse proxy part of the default stack.

**Acceptance:** a default start is reachable at `http://127.0.0.1:<port>` and not on a non-loopback host address. The explicit LAN option is documented as a trusted-LAN-only exception; the HTTPS proxy example remains the recommended remote-access path.

## WG-03: Resource and Availability Limits

**Intent:** contain accidental or malicious CPU, memory, PID, log, and Docker-storage exhaustion.

**Expected commit scope:** Compose limits for code-box, sandbox-dind, and Ollama where applicable, environment defaults, and validation of those settings in WG-00.

**Implementation direction:** add PID limits to every long-running service, add a CPU limit to DinD, and choose bounded Docker log rotation. Evaluate a storage quota or documented host-volume sizing for DinD before claiming Docker image storage is bounded.

**Acceptance:** rendered Compose settings include explicit limits for every service. A controlled process-limit test fails inside the disposable target without impairing the host or other containers. Docker image storage is documented as a host-volume capacity policy because Compose does not provide a portable quota control.

## WG-04: Reproducible and Verified Supply Chain

**Intent:** make a rebuild consume the intended base images, packages, and binaries.

**Expected commit scope:** image digests, artifact checksum/signature verification, build arguments for reviewed versions and checksums, and a documented update procedure.

**Implementation direction:** pin the LinuxServer base image, Docker DinD image, Ollama image, and other container references by digest after compatibility validation. Replace unchecked binary downloads and installer pipes with checksum or signature verification. Keep version labels readable alongside digests.

**Acceptance:** a tampered fixture checksum fails the build. The update procedure requires an intentional version-and-digest change. `docker build` reports the pinned artifact identities in a reviewable way.

## WG-05: Explicit Profile Selection

**Intent:** translate the three profiles into understandable, composable operator choices without creating a confusing matrix of defaults.

**Expected commit scope:** profile overlays or scripts, profile documentation, validation, and migration notes.

**Implementation direction:** retain the current developer experience as an explicitly selected local-functional profile. Add named overlays for contained builds and protected operation only after their controls exist. Profile names must describe a security posture rather than an implementation detail such as "advanced" or "strict".

**Acceptance:** every documented command declares its intended profile, resulting services and mounts are visible through `docker compose config`, and a user cannot enable a protected profile while inheriting unrestricted credential mounts by accident.

## WG-06: Credential and MCP Least Privilege

**Intent:** prevent routine agent tasks and nested builds from receiving an operator's full persistent credential state.

**Expected commit scope:** credential-mount design, GitHub and MCP defaults, profile-specific configuration, migration guidance, and tests with fake credentials.

**Design decision required before implementation:** choose whether protected operation uses separate credential directories, a broker/proxy for narrowly scoped operations, or explicit short-lived tokens. The choice must support `gh`, SSH, Claude, Cursor, and OpenCode without copying an operator's complete `/config` directory into a less-trusted profile.

**Implementation direction:** make read-only GitHub MCP and narrow toolsets the protected-profile default. Keep write operations and broad Actions access as explicit opt-ins. Do not mistake a read-only volume for credential containment when the agent can still exfiltrate readable tokens over the network.

**Acceptance:** a fake full credential store cannot be read by nested containers or a protected-profile agent. Protected MCP configuration exposes only the declared toolsets and rejects write operations by default.

## WG-07: Egress Policy

**Intent:** make outbound network access an explicit policy rather than an implicit capability of code-box and nested builds.

**Expected commit scope:** one selected enforcement mechanism, profile integration, host prerequisites, allowlist configuration, observability, and integration tests.

**Design decision required before implementation:** compare a host firewall on Docker bridges, an authenticated/transparent egress proxy, and a private registry/package mirror. Compose network declarations alone cannot reliably enforce a host-level egress boundary.

**Implementation direction:** start with an auditable policy that permits only DNS and required registries/package endpoints for contained builds. Protected operation should separately allow only required model, source-control, and package endpoints. The policy must specify how certificate validation, Git SSH, model providers, and package-manager mirrors are handled.

**Acceptance:** allowed registry/package access succeeds; an arbitrary external endpoint fails; DNS rebinding, container-IP access, loopback access, and proxy bypass attempts are covered by tests. The default local-functional profile remains explicit about broad egress.

## WG-08: Nested-to-Desktop Network Reduction

**Intent:** stop workloads launched by sandbox-dind from reaching KasmVNC and arbitrary services listening in code-box.

**Expected commit scope:** network topology or host-firewall rules, service bind-address guidance, integration tests, and threat-model updates.

**Design decision required before implementation:** select a design that preserves code-box-to-DinD TLS while restricting reverse traffic. Validate it with actual nested containers, not only Compose rendering.

**Acceptance:** code-box can control the sibling Docker daemon; nested containers cannot connect to KasmVNC or a test server bound in code-box; nested workloads retain only the egress allowed by WG-07.

## WG-09: Documentation and Release Gate

**Intent:** keep the threat model, quick start, deployment examples, and behavior of the shipped configuration aligned.

**Expected commit scope:** all affected documentation, a security-release checklist, and CI or release-runner integration for WG-00.

**Acceptance:** every claim in [threat-model.md](threat-model.md) names its implementation and test evidence. The quick start states its profile and exposure assumptions. The release process records image digests, smoke-test results, and any deliberately enabled compatibility exception.

## Non-Goals

- Multi-tenant isolation.
- A guarantee against a kernel, Docker, Sysbox, browser, or container-runtime escape.
- Blocking all internet use for the local-functional profile.
- Removing functionality solely to create a stronger security claim.

## Review Cadence

Update this document in the same pull request as each item. Mark an item complete only after its acceptance checks pass and the threat model reflects the shipped behavior. Add newly discovered work as a new `WG-xx` entry rather than expanding an in-progress commit beyond reviewable scope.
