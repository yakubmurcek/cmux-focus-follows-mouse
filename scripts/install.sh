#!/usr/bin/env bash
set -euo pipefail

# cmux-focus-follows-mouse installer

echo "==> Installing cmux-focus-follows-mouse (cmux-ffm)..."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: cmux-ffm is for macOS only." >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Error: swiftc not found. Install Xcode Command Line Tools via: xcode-select --install" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINDIR="${HOME}/.local/share/cmux-focus-follows-mouse"
LINKDIR="${HOME}/.local/bin"
PLIST_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.yakub.cmux-focus-follows-mouse"
PLIST="${PLIST_DIR}/${LABEL}.plist"

mkdir -p "${BINDIR}" "${LINKDIR}" "${PLIST_DIR}"

echo "==> Compiling cmux-ffm..."
swiftc -O -o "${BINDIR}/cmux-ffm" "${REPO_DIR}/Sources/main.swift"
ln -sf "${BINDIR}/cmux-ffm" "${LINKDIR}/cmux-ffm"

echo "==> Configuring LaunchAgent..."
cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BINDIR}/cmux-ffm</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>/tmp/cmux-ffm.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/cmux-ffm.log</string>
</dict>
</plist>
PLIST

echo "==> Loading LaunchAgent into launchd..."
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST}"

# Check cmux configuration for automation socket mode
CMUX_CONFIG="${HOME}/.config/cmux/cmux.json"
if [[ -f "${CMUX_CONFIG}" ]]; then
  if ! grep -q '"socketControlMode"[[:space:]]*:[[:space:]]*"automation"' "${CMUX_CONFIG}" 2>/dev/null; then
    echo ""
    echo "Notice: cmux requires automation socketControlMode so external daemons can connect."
    echo "Add the following setting to ${CMUX_CONFIG}:"
    echo '  "automation": {'
    echo '    "socketControlMode": "automation"'
    echo '  }'
  fi
fi

echo ""
echo "==> Running doctor check..."
"${BINDIR}/cmux-ffm" --doctor

echo ""
echo "✓ Installation complete! Hover over any cmux pane to focus it without clicking."
