#!/usr/bin/env bash
set -euo pipefail

echo "==> Uninstalling cmux-focus-follows-mouse (cmux-ffm)..."

LABEL="com.yakub.cmux-focus-follows-mouse"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
BINDIR="${HOME}/.local/share/cmux-focus-follows-mouse"
LINK="${HOME}/.local/bin/cmux-ffm"

if [[ -f "${PLIST}" ]]; then
  echo "Unloading LaunchAgent..."
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  rm -f "${PLIST}"
fi

rm -f "${LINK}"
rm -rf "${BINDIR}"
rm -f /tmp/cmux-ffm.log

echo "✓ Uninstallation complete."
