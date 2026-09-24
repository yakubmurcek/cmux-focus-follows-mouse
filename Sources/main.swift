//
//  main.swift
//  cmux-focus-follows-mouse (cmux-ffm)
//
//  Focus-follows-mouse daemon for cmux terminal multiplexer.
//  Polls the pointer; when it rests over a different cmux pane, focuses that pane.
//  Zero TCC permissions required. Only acts while cmux is frontmost.
//
//  Created by Jakub Murcek on 2026-09-06.
//  Licensed under the MIT License.
//

import Cocoa

let version = "1.0.0"

// MARK: - Configuration & CLI Arguments

struct Config {
    var cmuxBin: String = {
        let appBundleBin = "/Applications/cmux.app/Contents/Resources/bin/cmux"
        if FileManager.default.isExecutableFile(atPath: appBundleBin) {
            return appBundleBin
        }
        // Fallback to PATH lookup
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for dir in pathDirs {
            let candidate = (dir as NSString).appendingPathComponent("cmux")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return appBundleBin
    }()

    var pollInterval: TimeInterval = 0.05       // 50ms polling loop
    var dwellSeconds: TimeInterval = 0.05       // Pointer must rest in new pane this long
    var activeWindow: TimeInterval = 1.0        // Active evaluation window after last mouse move
    var layoutMaxAge: TimeInterval = 0.5        // Max age of cached pane layout before refreshing
    var debug: Bool = false
}

var config = Config()

// MARK: - Models

struct PaneRect {
    let ref: String
    let x, y, w, h: Double
    let focused: Bool

    func contains(_ px: Double, _ py: Double) -> Bool {
        px >= x && px < x + w && py >= y && py < y + h
    }
}

struct Layout {
    let workspaceRef: String
    let windowRef: String
    let containerW: Double
    let containerH: Double
    let panes: [PaneRect]
    let fetchedAt: Date
}

// MARK: - Subprocess Execution

@discardableResult
func runCmux(_ args: [String], quiet: Bool = true) -> (output: String?, exitCode: Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: config.cmuxBin)
    p.arguments = args

    var env = ProcessInfo.processInfo.environment
    if quiet {
        env["CMUX_QUIET"] = "1"
    }
    p.environment = env

    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err

    do {
        try p.run()
    } catch {
        return (nil, -1)
    }

    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(data: data, encoding: .utf8)
    return (text, p.terminationStatus)
}

// MARK: - Layout Discovery

func fetchLayout() -> Layout? {
    let (wsRaw, wsStatus) = runCmux(["workspace", "list", "--json"])
    guard wsStatus == 0,
          let wsRaw = wsRaw,
          let wsData = wsRaw.data(using: .utf8),
          let wsJSON = try? JSONSerialization.jsonObject(with: wsData) as? [String: Any],
          let windowRef = wsJSON["window_ref"] as? String,
          let workspaces = wsJSON["workspaces"] as? [[String: Any]] else {
        return nil
    }

    // The workspace currently shown in the key window is the selected one.
    let selected = workspaces.first { ($0["selected"] as? Bool) ?? false }
        ?? workspaces.first { ($0["focused"] as? Bool) ?? false }
        ?? workspaces.first
    guard let wsRef = selected?["ref"] as? String else { return nil }

    let (raw, panesStatus) = runCmux(["list-panes", "--workspace", wsRef, "--json"])
    guard panesStatus == 0,
          let raw = raw,
          let data = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let container = json["container_frame"] as? [String: Any],
          let cw = container["width"] as? Double,
          let ch = container["height"] as? Double,
          let panesRaw = json["panes"] as? [[String: Any]] else {
        return nil
    }

    var panes: [PaneRect] = []
    for p in panesRaw {
        guard let ref = p["ref"] as? String,
              let f = p["pixel_frame"] as? [String: Any],
              let x = f["x"] as? Double, let y = f["y"] as? Double,
              let w = f["width"] as? Double, let h = f["height"] as? Double else { continue }
        panes.append(PaneRect(ref: ref, x: x, y: y, w: w, h: h,
                              focused: (p["focused"] as? Bool) ?? false))
    }
    guard !panes.isEmpty else { return nil }
    return Layout(workspaceRef: wsRef, windowRef: windowRef,
                  containerW: cw, containerH: ch, panes: panes, fetchedAt: Date())
}

// MARK: - Window & Pointer Geometry

/// Frontmost on-screen cmux window (layer 0) whose bounds contain the pointer point.
/// CGWindowListCopyWindowInfo bounds do not require Accessibility TCC permission.
func cmuxWindowBounds(containing pt: CGPoint) -> CGRect? {
    guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in info {
        guard let owner = w[kCGWindowOwnerName as String] as? String,
              owner.lowercased().contains("cmux"),
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double,
              width > 200, height > 200 else { continue }
        let rect = CGRect(x: x, y: y, width: width, height: height)
        if rect.contains(pt) {
            return rect // list is front-to-back, first match wins
        }
    }
    return nil
}

/// Converts NSEvent.mouseLocation (bottom-left origin) to CoreGraphics global coordinates (top-left origin).
func globalPointerLocation() -> CGPoint {
    let m = NSEvent.mouseLocation
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    return CGPoint(x: m.x, y: primaryHeight - m.y)
}

func isCmuxFrontmost() -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication else { return false }
    let name = (front.localizedName ?? "").lowercased()
    let bundle = (front.bundleIdentifier ?? "").lowercased()
    return name.contains("cmux") || bundle.contains("cmux")
}

// MARK: - Main Loop State

var layout: Layout?
var lastWindowRect: CGRect?
var lastPointer: CGPoint?
var candidateRef: String?
var candidateSince = Date.distantPast
var lastMoveAt = Date.distantPast
var lastFocusedRef: String?

func tick() {
    guard isCmuxFrontmost() else {
        candidateRef = nil
        return
    }
    // Don't fight drags or resizes
    guard NSEvent.pressedMouseButtons == 0 else { return }

    let pt = globalPointerLocation()
    let moved = lastPointer.map { abs($0.x - pt.x) >= 1 || abs($0.y - pt.y) >= 1 } ?? true
    if moved {
        lastPointer = pt
        lastMoveAt = Date()
    }

    // A parked pointer never steals focus back (so manual clicks or keyboard navigation stick),
    // but keep evaluating briefly after the last move so a dwell can complete.
    guard Date().timeIntervalSince(lastMoveAt) < config.activeWindow else {
        candidateRef = nil
        return
    }

    guard let win = cmuxWindowBounds(containing: pt) else { return }

    if layout == nil || lastWindowRect != win || Date().timeIntervalSince(layout!.fetchedAt) > config.layoutMaxAge {
        layout = fetchLayout()
        lastWindowRect = win
        lastFocusedRef = layout?.panes.first(where: { $0.focused })?.ref
    }
    guard let lay = layout, lay.panes.count > 1 else { return }

    // Hit-testing:
    // cmux returns pixel_frame coordinates that are already window-relative
    // (pixel_frame.x dynamically accounts for the left sidebar's visibility and current width).
    func hit(_ l: Layout) -> PaneRect? {
        let px = pt.x - win.origin.x
        let py = pt.y - win.origin.y
        return l.panes.first { $0.contains(px, py) }
    }

    guard let target = hit(lay) else {
        candidateRef = nil
        return
    }
    if target.ref == lastFocusedRef {
        candidateRef = nil
        return
    }

    if candidateRef != target.ref {
        candidateRef = target.ref
        candidateSince = Date()
        if config.debug {
            print("[debug] Candidate pane: \(target.ref) at pt=(\(Int(pt.x)), \(Int(pt.y)))")
        }
    }
    guard Date().timeIntervalSince(candidateSince) >= config.dwellSeconds else { return }

    // Confirm against fresh geometry before switching focus
    guard let fresh = fetchLayout() else { return }
    layout = fresh
    guard let confirmed = hit(fresh), !confirmed.focused else {
        lastFocusedRef = fresh.panes.first(where: { $0.focused })?.ref
        candidateRef = nil
        return
    }

    if config.debug {
        print("[debug] Focusing pane \(confirmed.ref) (workspace \(fresh.workspaceRef))")
    }
    runCmux([
        "focus-pane",
        "--pane", confirmed.ref,
        "--workspace", fresh.workspaceRef,
        "--window", fresh.windowRef
    ])
    lastFocusedRef = confirmed.ref
    candidateRef = nil
}

// MARK: - Doctor Command

func runDoctor() {
    print("=== cmux-focus-follows-mouse doctor ===")
    print("Version: \(version)\n")

    // 1. Binary check
    let binExists = FileManager.default.isExecutableFile(atPath: config.cmuxBin)
    if binExists {
        print("[✓] cmux CLI binary found: \(config.cmuxBin)")
    } else {
        print("[✗] cmux CLI binary missing at: \(config.cmuxBin)")
        print("    Ensure cmux is installed in /Applications/cmux.app or on PATH.")
    }

    // 2. Running application check
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.cmuxterm.app")
    if let app = apps.first {
        print("[✓] cmux is running (PID: \(app.processIdentifier))")
    } else {
        print("[!] cmux is not currently running.")
    }

    // 3. Socket control check
    if binExists {
        let (output, exitCode) = runCmux(["workspace", "list", "--json"], quiet: false)
        if exitCode == 0, output != nil {
            print("[✓] Socket communication succeeded (socket control mode is properly set)")
        } else {
            print("[✗] Socket communication failed (exit code \(exitCode))")
            print("    cmux requires automation control mode for external daemons.")
            print("    Check ~/.config/cmux/cmux.json and ensure it has:")
            print("    { \"automation\": { \"socketControlMode\": \"automation\" } }")
        }
    }

    // 4. Window bounds check via CoreGraphics
    let pt = globalPointerLocation()
    if let win = cmuxWindowBounds(containing: pt) {
        print("[✓] Active cmux window detected under pointer: bounds=\(win)")
    } else {
        print("[i] Pointer is not currently over a frontmost cmux window (normal if running in another terminal).")
    }

    // 5. LaunchAgent check
    let label = "com.yakub.cmux-focus-follows-mouse"
    let plistPath = ("~/Library/LaunchAgents/\(label).plist" as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: plistPath) {
        print("[✓] LaunchAgent plist installed at: \(plistPath)")
        let (listOut, _) = runCommand(["launchctl", "list"])
        if (listOut ?? "").contains(label) {
            print("[✓] LaunchAgent is loaded and running in launchd.")
        } else {
            print("[!] LaunchAgent plist exists but is not currently loaded in launchd.")
            print("    Load with: launchctl bootstrap gui/$(id -u) \(plistPath)")
        }
    } else {
        print("[i] LaunchAgent plist not found at: \(plistPath)")
        print("    Install with: make install")
    }

    print("\nDoctor check completed.")
}

func runCommand(_ args: [String]) -> (String?, Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do {
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8), p.terminationStatus)
    } catch {
        return (nil, -1)
    }
}

// MARK: - CLI Entrypoint

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("""
    cmux-focus-follows-mouse (cmux-ffm) v\(version)
    Focus-follows-mouse daemon for the cmux terminal multiplexer.

    Usage:
      cmux-ffm [flags]

    Flags:
      -h, --help            Show this help text
      -v, --version         Show version
      --doctor              Diagnose cmux connection, socket permissions, and LaunchAgent
      --debug               Run in foreground with verbose event logging
      --dwell <seconds>     Time pointer must rest in pane before focusing (default: 0.05)
      --poll <seconds>      Polling interval in seconds (default: 0.05)

    Source & Issues:
      https://github.com/yakubmurcek/cmux-focus-follows-mouse
    """)
    exit(0)
}

if args.contains("--version") || args.contains("-v") {
    print("cmux-ffm v\(version)")
    exit(0)
}

if args.contains("--doctor") {
    runDoctor()
    exit(0)
}

if args.contains("--debug") {
    config.debug = true
    print("cmux-ffm v\(version) running in debug mode...")
}

if let dwellIdx = args.firstIndex(of: "--dwell"), dwellIdx + 1 < args.count,
   let d = Double(args[dwellIdx + 1]), d > 0 {
    config.dwellSeconds = d
}

if let pollIdx = args.firstIndex(of: "--poll"), pollIdx + 1 < args.count,
   let p = Double(args[pollIdx + 1]), p > 0 {
    config.pollInterval = p
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Timer.scheduledTimer(withTimeInterval: config.pollInterval, repeats: true) { _ in tick() }
RunLoop.main.run()
