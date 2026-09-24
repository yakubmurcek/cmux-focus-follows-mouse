# cmux-focus-follows-mouse (cmux-ffm)

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/yakubmurcek/cmux-focus-follows-mouse/actions/workflows/build.yml/badge.svg)](https://github.com/yakubmurcek/cmux-focus-follows-mouse/actions/workflows/build.yml)

A lightweight, zero-latency **focus-follows-mouse (hover autofocus)** daemon for the [cmux](https://cmux.com) terminal multiplexer on macOS.

Hover your cursor over any terminal pane to focus it immediately—no clicking required.

---

## Why this exists

cmux does not provide a native focus-follows-mouse configuration option (`app.focusPaneOnFirstClick` only affects clicks, not hover). 

`cmux-ffm` runs as a lightweight background daemon that bridges this gap. It hit-tests cursor movement against live cmux pane geometry via the local cmux automation socket, switching pane focus seamlessly.

## Key Features

- ⚡ **True hover autofocus**: Automatically switches focus to the pane under your pointer.
- 📐 **Dynamic layout awareness**: Accurately tracks arbitrary pane splits (horizontal & vertical), open/closed left workspace sidebars, dynamically resized sidebar widths, and right sidebars.
- 🧠 **Smart dwell & sticky focus**: 
  - **50ms dwell**: Prevents accidental focus theft while moving across panes.
  - **Sticky focus**: A parked pointer never steals focus back. Manual clicks or keyboard shortcuts (like `⌥⌘-Arrow` or `Cmd+[`/`Cmd+]`) stay focused until you deliberately move the mouse into another pane.
- 🔒 **Zero TCC Accessibility permissions**: Hit-tests using public CoreGraphics window bounds (`CGWindowListCopyWindowInfo`) and cmux socket APIs. No Accessibility (`AXUIElement`) or screen recording permissions needed.
- 🔋 **Battery-efficient**: Polls only when cmux is frontmost, halts evaluation when the mouse is stationary, and ignores cursor movement while mouse buttons are held down (preventing interference with text selection or divider drags).
- 🩺 **Built-in diagnostics**: Run `cmux-ffm --doctor` to verify socket connectivity, binary resolution, and daemon state in seconds.

---

## Quick Start

### 1. Enable cmux Automation Socket

cmux requires external processes to connect in `automation` mode. Ensure your `~/.config/cmux/cmux.json` contains:

```jsonc
{
  "automation": {
    "socketControlMode": "automation"
  }
}
```

Reload cmux configuration with `cmux config reload`.

### 2. Install & Start Daemon

Clone the repository and run `make install`:

```bash
git clone https://github.com/yakubmurcek/cmux-focus-follows-mouse.git
cd cmux-focus-follows-mouse
make install
```

This compiles the binary with optimization (`-O`), installs it to `~/.local/share/cmux-focus-follows-mouse/cmux-ffm`, creates a symlink in `~/.local/bin/cmux-ffm`, and registers a `launchd` service that starts automatically at login.

---

## Verifying Setup

Run the built-in diagnostic doctor:

```bash
cmux-ffm --doctor
```

Expected output:
```text
=== cmux-focus-follows-mouse doctor ===
Version: 1.0.0

[✓] cmux CLI binary found: /Applications/cmux.app/Contents/Resources/bin/cmux
[✓] cmux is running (PID: 43466)
[✓] Socket communication succeeded (socket control mode is properly set)
[✓] Active cmux window detected under pointer: bounds=(0.0, 34.0, 1470.0, 857.0)
[✓] LaunchAgent plist installed at: /Users/yakub/Library/LaunchAgents/com.yakub.cmux-focus-follows-mouse.plist
[✓] LaunchAgent is loaded and running in launchd.

Doctor check completed.
```

To watch live focus events in real time:

```bash
cmux-ffm --debug
```

---

## How It Works

```
                        ┌─────────────────────────────────┐
                        │   Mouse Pointer (CoreGraphics)  │
                        └───────────────┬─────────────────┘
                                        │ (50ms poll while cmux frontmost)
                                        ▼
                        ┌─────────────────────────────────┐
                        │    cmux Window Bounds Check     │
                        └───────────────┬─────────────────┘
                                        │
                                        ▼
                        ┌─────────────────────────────────┐
                        │  Hit-test cmux list-panes JSON  │
                        │  (Dynamic window-relative rects)│
                        └───────────────┬─────────────────┘
                                        │
                         [ resting dwell >= 50ms ]
                                        │
                                        ▼
                        ┌─────────────────────────────────┐
                        │    cmux focus-pane --pane <ref> │
                        └─────────────────────────────────┘
```

1. **Pointer Monitoring**: Monitors global cursor position every 50ms using `NSEvent.mouseLocation`. Stops evaluating after 1 second of inactivity to eliminate idle CPU cycles.
2. **Window Association**: Resolves the frontmost cmux window on layer 0 containing the pointer.
3. **Geometry Hit-Testing**: Evaluates pointer location against `cmux list-panes --json`. The pane `pixel_frame` coordinates reported by cmux are window-relative and dynamically include the left sidebar's current width.
4. **Dwell Confirmation**: Once the pointer enters a candidate pane, a 50ms dwell timer ensures the cursor is resting rather than traveling through. It re-verifies against fresh geometry before issuing `cmux focus-pane`.

---

## CLI Options

```text
Usage: cmux-ffm [flags]

Flags:
  -h, --help            Show help text
  -v, --version         Show version
  --doctor              Diagnose connection, socket configuration, and launchd status
  --debug               Run in foreground with verbose event logging
  --dwell <seconds>     Time pointer must rest in pane before focusing (default: 0.05)
  --poll <seconds>      Polling interval in seconds (default: 0.05)
```

---

## Managing the Daemon

- **View logs**:
  ```bash
  tail -f /tmp/cmux-ffm.log
  ```
- **Restart daemon**:
  ```bash
  make reload
  ```
- **Stop / Uninstall**:
  ```bash
  make uninstall
  ```

---

## Requirements

- **OS**: macOS 13.0 (Ventura) or newer
- **Terminal Multiplexer**: [cmux](https://cmux.com) (installed in `/Applications/cmux.app` or available on `PATH`)
- **Compiler**: `swiftc` (available via Xcode or `xcode-select --install`)

---

## License

[MIT](LICENSE) © [Jakub Murcek](https://github.com/yakubmurcek)
