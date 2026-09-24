# Browser tools (Playwright MCP)

Cursor, Claude Code, and OpenCode drive a real browser through Microsoft [Playwright MCP](https://github.com/microsoft/playwright-mcp). That is how agents verify UI in code-box. GitHub and Fetch MCP are documented in [mcp.md](mcp.md).

Cursor’s **built-in** browser (`cursor-ide-browser`) often does not expose tools in this Linux GUI / container. The agent then says it has no browser tools. Do not rely on Settings → Browser Automation; use the seeded **playwright** MCP server.

Firefox stays the interactive desktop browser. Agents use Playwright’s **Chromium** (headless).

HOME is `/config` (host `./data/config`). MCP configs are seeded on first desktop start and are not overwritten if you already have a `playwright` entry.

## What the image provides

| Piece | Role |
|-------|------|
| `/usr/local/bin/playwright-mcp` | Wrapper: loads nvm, `--headless --browser chromium --no-sandbox` |
| `/opt/ms-playwright` | MCP Chromium only (wrapper sets `PLAYWRIGHT_BROWSERS_PATH`; not writable) |
| `~/.cursor/mcp.json` | Cursor MCP (`command` is the wrapper) |
| `~/.claude.json` | Claude Code `mcpServers.playwright` |
| `~/.config/opencode/opencode.json` | OpenCode `mcp.playwright` |

`--no-sandbox` is required in Docker. `shm_size` (1gb) and `seccomp=unconfined` are already set on the desktop container. Why, and what that trades away: [threat-model.md](threat-model.md#deliberately-open).

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
DISPLAY=:1 PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
  "$(npm prefix -g)/bin/playwright-mcp" --browser chromium --no-sandbox
```

Point a client at that process only if you know you need headed mode. Keep the wrapper headless for Agent testing.

## Project tests (Playwright, Cypress, Puppeteer)

MCP Chromium is **not** the visual-regression / e2e browser. Image `PLAYWRIGHT_BROWSERS_PATH` is unset at runtime so project tools use `$HOME/.cache/...` (`/config`, uid 1000). `/opt/ms-playwright` stays root-owned so agents cannot overwrite MCP’s browser.

```bash
npx playwright install chromium    # OK — binaries under ~/.cache/ms-playwright
npx playwright install --with-deps # will fail — no sudo; Chromium libs are already in the image
```

Downloads persist on the `/config` volume (once per Playwright pin, not per session). Pixel gates must use the **project** `@playwright/test` pin, same as CI — do not point `executablePath` at `/opt/ms-playwright`.

In this container Chromium still needs `--no-sandbox` (the MCP wrapper already passes it). Set the same launch args in the **product** `playwright.config` if tests crash after a successful install. Do not rewrite product configs as a sandbox workaround.

Playwright Firefox/WebKit: `npx playwright install firefox` (binaries only) is allowed; `install-deps` for those engines is not. Cypress and Puppeteer already cache under `~/.cache` (we do not set `CYPRESS_CACHE_FOLDER` or `PUPPETEER_CACHE_DIR`).

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
| `Executable doesn't exist` (MCP) | Rebuild so MCP Chromium lands in `/opt/ms-playwright`. |
| `Executable doesn't exist` (project tests) | `npx playwright install chromium` (no `--with-deps`). Browsers go to `~/.cache/ms-playwright`, not `/opt`. |
| `EACCES` / `__dirlock` under `/opt/ms-playwright` | Image still exporting `PLAYWRIGHT_BROWSERS_PATH`. Rebuild so that ENV is gone; MCP wrapper sets it only for itself. |
| Project Chromium crash / sandbox | Product config needs `--no-sandbox`, same as the MCP wrapper. Confirm `shm_size` is 1gb. |
| Existing `mcp.json` without playwright | Seed only fills a missing `playwright` key (or a missing Cursor file). Add the block by hand if jq merge did not run. |
