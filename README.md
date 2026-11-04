# cmux-focus-follows-mouse (cmux-ffm)

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![CI](https://github.com/yakubmurcek/cmux-focus-follows-mouse/actions/workflows/build.yml/badge.svg)](https://github.com/yakubmurcek/cmux-focus-follows-mouse/actions/workflows/build.yml)

A lightweight, zero-latency **focus-follows-mouse (hover autofocus)** daemon for the [cmux](https://cmux.com) terminal multiplexer on macOS.

Hover your cursor over any terminal pane to focus it immediately—no clicking required.

> [!TIP]
> **Try the built-in option first.** Since **cmux 0.62.0**, cmux honors Ghostty's own
> `focus-follows-mouse` setting ([manaflow-ai/cmux#519](https://github.com/manaflow-ai/cmux/pull/519)).
> Add this line to `~/.config/ghostty/config` and restart cmux:
>
> ```
> focus-follows-mouse = true
> ```
>
> That needs no daemon and no automation socket. Use `cmux-ffm` only if you want what the
> built-in option doesn't do (see below), or if you run a cmux older than 0.62.0.

---

## Why this exists

Older cmux versions ignored Ghostty's `focus-follows-mouse`, and cmux's own `app.focusPaneOnFirstClick` only affects clicks, not hover. `cmux-ffm` was written to fill that gap.

What it still does differently from the built-in option:

| | built-in `focus-follows-mouse` | `cmux-ffm` |
|---|---|---|
| Focus switch | the moment the pointer enters a terminal | after the pointer rests 50 ms (tunable with `--dwell`), so sweeping across panes doesn't move focus |
| Panes it can focus | terminal surfaces | every pane `cmux list-panes` reports, via `cmux focus-pane` |
| Setup | one config line | a LaunchAgent + cmux socket in `automation` mode |

`cmux-ffm` runs as a lightweight background daemon. It hit-tests cursor movement against live cmux pane geometry via the local cmux automation socket and switches pane focus with `cmux focus-pane`.

## Key Features

- ⚡ **True hover autofocus**: Automatically switches focus to the pane under your pointer.
- 📐 **Dynamic layout awareness**: Accurately tracks arbitrary pane splits (horizontal & vertical), open/closed left workspace sidebars, dynamically resized sidebar widths, and right sidebars.
- 🧠 **Smart dwell & sticky focus**: 
  - **50ms dwell**: Prevents accidental focus theft while moving across panes.
  - **Sticky focus**: A parked pointer never steals focus back. Manual clicks or keyboard shortcuts (like `⌥⌘-Arrow` or `Cmd+[`/`Cmd+]`) stay focused until you deliberately move the mouse into another pane.
- 🔒 **Zero TCC Accessibility permissions**: Hit-tests using public CoreGraphics window bounds (`CGWindowListCopyWindowInfo`) and cmux socket APIs. No Accessibility (`AXUIElement`) or screen recording permissions needed.
- 🔋 **Battery-efficient**: Sleeps until cmux becomes the active app (no polling at all while you're elsewhere), halts evaluation when the mouse is stationary, and ignores cursor movement while mouse buttons are held down (preventing interference with text selection or divider drags).
- 🧯 **Can't hang**: every cmux call has a 3 s timeout, so a stuck cmux CLI can't freeze the daemon.
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
Version: 1.1.0

[✓] cmux CLI binary found: /Applications/cmux.app/Contents/Resources/bin/cmux
[✓] cmux is running (PID: 43466)
[✓] Socket communication succeeded (socket control mode is properly set)
[✓] Active cmux window detected under pointer: bounds=(0.0, 34.0, 1470.0, 857.0)
[✓] LaunchAgent plist installed at: /Users/yakub/Library/LaunchAgents/com.yakub.cmux-focus-follows-mouse.plist
[✓] LaunchAgent is loaded and running in launchd.

Doctor check completed.
```

If cmux is not running, the doctor says so and skips the socket test instead of blaming your config.

To print the pane rectangles cmux reports (what the daemon hit-tests against):

```bash
cmux-ffm --layout
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

1. **Pointer Monitoring**: While cmux is the active app, monitors global cursor position every 50ms using `NSEvent.mouseLocation`. Stops evaluating after 1 second of inactivity, and stops the timer entirely when another app becomes active.
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
  --layout              Print the pane rectangles cmux reports, then exit
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

## Tests

```bash
make test
```

Runs the daemon against fake `cmux` CLIs (in `tests/fake-cmux/`): pane parsing, a cmux call that floods stderr, and one that never returns. No cmux install needed; CI runs the same.

---

## Requirements

- **OS**: macOS 13.0 (Ventura) or newer
- **Terminal Multiplexer**: [cmux](https://cmux.com) (installed in `/Applications/cmux.app` or available on `PATH`)
- **Compiler**: `swiftc` (available via Xcode or `xcode-select --install`)

---

## License

[MIT](LICENSE) © [Jakub Murcek](https://github.com/yakubmurcek)
