# Release Checklist

Complete this checklist before creating a `vMAJOR.MINOR.PATCH` release. Record the results and any exceptions in the release pull request or release notes.

## Automated Gate

```bash
scripts/release-check.sh
```

This runs the artifact checksum tamper test, all disposable containment checks, profile/overlay rendering, Sysbox DinD checks when available, and base/protected Compose validation.

## Image Identity

- [ ] Record the release commit SHA.
- [ ] Record the local image identity: `docker image inspect local/code-box:3.14 --format '{{.Id}}'`.
- [ ] Review any changed container image digest or direct-download SHA-256 against its upstream release.
- [ ] Review `docs/supply-chain.md` update steps for every changed external input.

## Profile Smoke Tests

- [ ] Local functional development: desktop login, Cursor, VS Code, Firefox, Claude Code, OpenCode, and MCP wrappers work.
- [ ] Contained build execution: `scripts/up.sh --profile contained-build`; `docker info` works from the desktop.
- [ ] Protected agent operation: `scripts/up.sh --profile protected-agent`; rendered config mounts only `./data/config-protected` at `/config`.
- [ ] If selected, verify `scripts/up.sh --seccomp-unconfined` is documented as a host-specific compatibility exception and record why it remains enabled.

## Host-Enforced Controls

Run these checks on the release host whenever egress proxy or sandbox isolation is enabled.

- [ ] Proxy allowlist permits the required registry/package/model/source-control destinations.
- [ ] Direct arbitrary external access, direct DNS, and proxy-bypass access fail from code-box and a nested DinD workload.
- [ ] `sudo ./scripts/apply-sandbox-isolation.sh` is applied after container creation.
- [ ] `docker exec code-box docker info` succeeds after isolation is applied.
- [ ] A new nested workload cannot connect to code-box's `sandbox-net` address on port 3000 or a test listener.
- [ ] Firewall rules and proxy allowlist were reviewed; removal commands were tested before a network recreation.

## Release Notes

- [ ] State the selected profile(s), whether a proxy/isolation policy is active, and any egress allowlist exceptions.
- [ ] State whether protected profile credentials are fine-grained/read-only and where their operator-provisioned state resides.
- [ ] Link the threat model and list remaining deliberate openings relevant to the deployment.
