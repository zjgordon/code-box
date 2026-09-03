# Browser tools (Playwright MCP)

Cursor, Claude Code, and OpenCode drive a real browser through Microsoft [Playwright MCP](https://github.com/microsoft/playwright-mcp). That is how agents verify UI in code-box. GitHub and Fetch MCP are documented in [mcp.md](mcp.md).

Cursor’s **built-in** browser (`cursor-ide-browser`) often does not expose tools in this Linux GUI / container. The agent then says it has no browser tools. Do not rely on Settings → Browser Automation; use the seeded **playwright** MCP server.

Firefox stays the interactive desktop browser. Agents use Playwright’s **Chromium** (headless).

HOME is `/config` (host `./data/config`). MCP configs are seeded on first desktop start and are not overwritten if you already have a `playwright` entry.

## What the image provides

| Piece | Role |
|-------|------|
| `/usr/local/bin/playwright-mcp` | Wrapper: loads nvm, `--headless --browser chromium --no-sandbox` |
| `/opt/ms-playwright` | Playwright Chromium (`PLAYWRIGHT_BROWSERS_PATH`) |
| `~/.cursor/mcp.json` | Cursor MCP (`command` is the wrapper) |
| `~/.claude.json` | Claude Code `mcpServers.playwright` |
| `~/.config/opencode/opencode.json` | OpenCode `mcp.playwright` |

`--no-sandbox` is required in Docker. `shm_size` (1gb) and `seccomp=unconfined` are already set on the desktop container.

The wrapper sources nvm because Cursor is launched as a GUI app and does not load `bashrc`. Do not point MCP at `npx @playwright/mcp@latest`.

## Cursor

1. Restart Cursor after the first desktop login (so it reads `~/.cursor/mcp.json`).
2. Open **Settings → Tools & MCP**. Enable **playwright** if the tools are toggled off.
3. In Agent mode, ask it to open a URL (for example `https://example.com`) and snapshot the page.

You should see tools such as `browser_navigate` and `browser_snapshot`.

## Claude Code

In a session: `/mcp`. **playwright** should be connected. Same wrapper as Cursor.

## OpenCode

`mcp.playwright` is merged into `~/.config/opencode/opencode.json` if missing. The example at `/workspace/opencode.json.example` includes the same block. Restart the TUI after the first seed.

## Headed Chromium on XFCE (optional)

Default is headless so Cursor’s MCP worker does not need `DISPLAY`. To watch the browser on the desktop, run the upstream CLI with a display (KasmVNC is usually `:1`):

```bash
DISPLAY=:1 "$(npm prefix -g)/bin/playwright-mcp" --browser chromium --no-sandbox
```

Point a client at that process only if you know you need headed mode. Keep the wrapper headless for Agent testing.

## Smoke checks

```bash
/usr/local/bin/playwright-mcp --help
ls /opt/ms-playwright
# Chromium launch (no page automation):
find /opt/ms-playwright -type f -name chrome -executable | head -1
```

After the desktop has started: `jq . ~/.cursor/mcp.json`.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Agent has no browser tools | Settings → Tools & MCP: **playwright** enabled; restart Cursor. Built-in Browser Automation is not used. |
| MCP red / 0 tools | `/usr/local/bin/playwright-mcp --help`; Chromium under `/opt/ms-playwright`. |
| `npx: command not found` in MCP logs | Config must use `/usr/local/bin/playwright-mcp`, not `npx`. |
| `Executable doesn't exist` | Rebuild the image so browsers land in `/opt/ms-playwright`. |
| Chromium crash / sandbox | Wrapper already passes `--no-sandbox`. Confirm `shm_size` is 1gb. |
| Existing `mcp.json` without playwright | Seed only fills a missing `playwright` key (or a missing Cursor file). Add the block by hand if jq merge did not run. |
