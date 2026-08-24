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
