#!/usr/bin/env bash
# XFCE session. Seed autostart entries from image (fixes stale /config copy).
# Base image uses /defaults/autostart as a file; keep Cursor entries in xfce-autostart/
mkdir -p "${HOME:-/config}/.config/autostart"
cp -f /defaults/xfce-autostart/*.desktop "${HOME:-/config}/.config/autostart/" 2>/dev/null || true
if command -v xdg-settings &>/dev/null; then
  xdg-settings set default-web-browser firefox.desktop 2>/dev/null || true
fi
sleep 1
exec dbus-launch --exit-with-session xfce4-session
