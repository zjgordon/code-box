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

# MCP: seed Cursor config if missing; merge into Cursor / Claude / OpenCode if a key is absent
if [ ! -f "${HOME}/.cursor/mcp.json" ] && [ -f /defaults/cursor-mcp.json ]; then
  mkdir -p "${HOME}/.cursor"
  cp -f /defaults/cursor-mcp.json "${HOME}/.cursor/mcp.json"
fi

seed_mcp_command() {
  # $1 = jq path to the server object (e.g. .mcpServers.github)
  # $2 = JSON value to assign
  # $3 = file
  local path="$1" value="$2" file="$3"
  if ! jq -e "${path}" "${file}" >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq "${path} = ${value}" "${file}" >"$tmp"; then
      mv "$tmp" "${file}"
    else
      rm -f "$tmp"
    fi
  fi
}

if command -v jq >/dev/null; then
  if [ -f "${HOME}/.cursor/mcp.json" ]; then
    seed_mcp_command '.mcpServers.playwright' '{"command":"/usr/local/bin/playwright-mcp"}' "${HOME}/.cursor/mcp.json"
    seed_mcp_command '.mcpServers.github' '{"command":"/usr/local/bin/github-mcp"}' "${HOME}/.cursor/mcp.json"
    seed_mcp_command '.mcpServers.fetch' '{"command":"/usr/local/bin/fetch-mcp"}' "${HOME}/.cursor/mcp.json"
  fi

  claude_json="${HOME}/.claude.json"
  if [ ! -f "$claude_json" ]; then
    printf '%s\n' '{"mcpServers":{}}' >"$claude_json"
  fi
  seed_mcp_command '.mcpServers.playwright' '{"command":"/usr/local/bin/playwright-mcp"}' "$claude_json"
  seed_mcp_command '.mcpServers.github' '{"command":"/usr/local/bin/github-mcp"}' "$claude_json"
  seed_mcp_command '.mcpServers.fetch' '{"command":"/usr/local/bin/fetch-mcp"}' "$claude_json"

  oc_json="${HOME}/.config/opencode/opencode.json"
  mkdir -p "${HOME}/.config/opencode"
  if [ ! -f "$oc_json" ]; then
    printf '%s\n' '{"$schema":"https://opencode.ai/config.json"}' >"$oc_json"
  fi
  seed_mcp_command '.mcp.playwright' '{"type":"local","command":["/usr/local/bin/playwright-mcp"],"enabled":true}' "$oc_json"
  seed_mcp_command '.mcp.github' '{"type":"local","command":["/usr/local/bin/github-mcp"],"enabled":true}' "$oc_json"
  seed_mcp_command '.mcp.fetch' '{"type":"local","command":["/usr/local/bin/fetch-mcp"],"enabled":true}' "$oc_json"
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
