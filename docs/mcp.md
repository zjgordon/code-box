# Agent MCP tools

Cursor, Claude Code, and OpenCode share three seeded MCP servers. Wrappers live on `PATH`; do not point configs at `npx`, `uvx`, or `docker run`.

| Server | Wrapper | Role |
|--------|---------|------|
| **playwright** | `/usr/local/bin/playwright-mcp` | Headless Chromium for UI (see [browser.md](browser.md)) |
| **github** | `/usr/local/bin/github-mcp` | GitHub API: repos, issues, PRs, **Actions** (token from `gh auth`) |
| **fetch** | `/usr/local/bin/fetch-mcp` | HTTP GET → markdown (no browser) |

HOME is `/config` (host `./data/config`). On first desktop start, missing keys are merged into `~/.cursor/mcp.json`, `~/.claude.json`, and `~/.config/opencode/opencode.json`. Existing custom entries are not overwritten.

## GitHub

[github/github-mcp-server](https://github.com/github/github-mcp-server) is a **local binary** (`/usr/local/lib/github-mcp-server/github-mcp-server`). The wrapper sets `GITHUB_PERSONAL_ACCESS_TOKEN` from `gh auth token` and `GITHUB_TOOLSETS=default,actions`. Nothing is baked into the image.

1. Complete [GitHub login](github.md) (`gh auth login --web`).
2. Restart Cursor (or `/mcp` in Claude Code / restart OpenCode) so the server can start.
3. Ask the agent to list workflow runs or open a PR.

The same token scopes as `gh` apply (not read-only). Override toolsets with `GITHUB_TOOLSETS` on the wrapper environment if you need a smaller set.

Do **not** run `ghcr.io/github/github-mcp-server` on sibling DinD for this. Do **not** use the Copilot remote MCP URL unless you deliberately want a second OAuth path.

If the server fails with “needs gh auth”, the desktop user is not logged in. `gh auth status` in a terminal.

## Fetch

Pinned [`mcp-server-fetch`](https://pypi.org/project/mcp-server-fetch/) in `/opt/mcp-fetch`. The wrapper sources nvm (better HTML simplifier when Node is on `PATH`) and passes `--ignore-robots-txt` so agent doc fetches are not blocked by crawler rules.

Use Fetch for raw pages and APIs. Use Playwright when you need a real browser (JS apps, clicks, `http://sandbox-dind:<port>` UI).

Fetch can reach the same places `curl` can, including loopback and lab DNS (`127.0.0.1`, `ollama`, `sandbox-dind`). That is not a new hole; do not treat it as a browser sandbox.

## Cursor

1. Restart Cursor after the first desktop login.
2. **Settings → Tools & MCP**: enable **playwright**, **github**, and **fetch** if they are toggled off.

## Claude Code

`/mcp` should list the three servers.

## OpenCode

The example at `/workspace/opencode.json.example` includes the same blocks. Restart the TUI after the first seed.

## Smoke checks

```bash
/usr/local/bin/playwright-mcp --help
# GitHub binary (wrapper needs gh auth and speaks stdio, not --help):
/usr/local/lib/github-mcp-server/github-mcp-server --help
gh auth status
# Fetch venv:
/opt/mcp-fetch/bin/python -c "import mcp_server_fetch; print('ok')"
jq . ~/.cursor/mcp.json
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| MCP red / 0 tools | Wrapper `--help`; rebuild so pins land in the image. |
| `npx: command not found` | Config must use `/usr/local/bin/*-mcp`, not `npx`/`uvx`. |
| GitHub MCP: needs gh auth | [docs/github.md](github.md); `gh auth token` in a desktop terminal. |
| GitHub MCP: no Actions tools | Wrapper default is `default,actions`. Confirm `GITHUB_TOOLSETS` is unset or includes `actions`. |
| Fetch / Playwright overlap | Fetch = HTML/markdown GET. Playwright = Chromium. |
| Existing `mcp.json` without github/fetch | Seed only fills **missing** keys. Add by hand or delete the key and restart the desktop session. |
