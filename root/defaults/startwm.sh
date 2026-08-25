#!/usr/bin/env bash
# XFCE session. Seed autostart entries from image (fixes stale /config copy).
# Base image uses /defaults/autostart as a file; keep Cursor entries in xfce-autostart/
HOME="${HOME:-/config}"
mkdir -p "${HOME}/.config/autostart"
cp -f /defaults/xfce-autostart/*.desktop "${HOME}/.config/autostart/" 2>/dev/null || true

# Seed baked gh extensions once so later `gh extension upgrade` is not overwritten
if [ -d /opt/gh-share/gh/extensions ]; then
  mkdir -p "${HOME}/.local/share/gh/extensions"
  for ext in /opt/gh-share/gh/extensions/*; do
    [ -d "$ext" ] || continue
    name=$(basename "$ext")
    if [ ! -e "${HOME}/.local/share/gh/extensions/${name}" ]; then
      cp -a "$ext" "${HOME}/.local/share/gh/extensions/${name}"
    fi
  done
fi

# Playwright MCP: seed Cursor config if missing; merge into Claude / OpenCode if the key is absent
if [ ! -f "${HOME}/.cursor/mcp.json" ] && [ -f /defaults/cursor-mcp.json ]; then
  mkdir -p "${HOME}/.cursor"
  cp -f /defaults/cursor-mcp.json "${HOME}/.cursor/mcp.json"
fi
if command -v jq >/dev/null; then
  if [ -f "${HOME}/.cursor/mcp.json" ] \
     && ! jq -e '.mcpServers.playwright' "${HOME}/.cursor/mcp.json" >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq '.mcpServers.playwright = {"command":"/usr/local/bin/playwright-mcp"}' \
         "${HOME}/.cursor/mcp.json" >"$tmp"; then
      mv "$tmp" "${HOME}/.cursor/mcp.json"
    else
      rm -f "$tmp"
    fi
  fi

  claude_json="${HOME}/.claude.json"
  if [ ! -f "$claude_json" ]; then
    printf '%s\n' '{"mcpServers":{}}' >"$claude_json"
  fi
  if ! jq -e '.mcpServers.playwright' "$claude_json" >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq '.mcpServers.playwright = {"command":"/usr/local/bin/playwright-mcp"}' \
         "$claude_json" >"$tmp"; then
      mv "$tmp" "$claude_json"
    else
      rm -f "$tmp"
    fi
  fi

  oc_json="${HOME}/.config/opencode/opencode.json"
  mkdir -p "${HOME}/.config/opencode"
  if [ ! -f "$oc_json" ]; then
    printf '%s\n' '{"$schema":"https://opencode.ai/config.json"}' >"$oc_json"
  fi
  if ! jq -e '.mcp.playwright' "$oc_json" >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq '.mcp.playwright = {"type":"local","command":["/usr/local/bin/playwright-mcp"],"enabled":true}' \
         "$oc_json" >"$tmp"; then
      mv "$tmp" "$oc_json"
    else
      rm -f "$tmp"
    fi
  fi
fi

if command -v xdg-settings &>/dev/null; then
  xdg-settings set default-web-browser firefox.desktop 2>/dev/null || true
fi

export GH_BROWSER="${GH_BROWSER:-firefox}"
if [ -x /usr/bin/ssh-askpass ]; then
  export SSH_ASKPASS=/usr/bin/ssh-askpass
  export SSH_ASKPASS_REQUIRE=prefer
fi

# ssh-agent for passphrase-protected keys and SSH commit signing
if [ -z "${SSH_AUTH_SOCK:-}" ] && command -v ssh-agent >/dev/null; then
  eval "$(ssh-agent -s)" >/dev/null
fi

sleep 1
exec dbus-launch --exit-with-session xfce4-session
