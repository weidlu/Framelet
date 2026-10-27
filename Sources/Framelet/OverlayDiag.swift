import AppKit

/// Opt-in overlay diagnostics, retained for acceptance runs only.
///
/// Off by default: a normal launch must not write logs, and must never record
/// keystrokes or per-frame cursor work. Enable explicitly with
/// `--diag` / `FRAMELET_DIAG=1`; output goes to `--diag-log <path>` or
/// `<worktree>/work/overlay-diagnostic.log`. Every line is prefixed `[FL-DIAG]`.
/// Never records screen contents.
enum OverlayDiag {
    private static let prefix = "[FL-DIAG]"
    private static var handle: FileHandle?
    private static var started = false

    /// Off unless explicitly requested.
    static var enabled: Bool {
        if let value = ProcessInfo.processInfo.environment["FRAMELET_DIAG"] {
            return value == "1" || value.lowercased() == "true"
        }
        return ProcessInfo.processInfo.arguments.contains("--diag")
    }

    static func start() {
        guard enabled, !started else { return }
        started = true
        let path = logURL()
        FileManager.default.createFile(atPath: path.path, contents: nil)
        handle = FileHandle(forWritingAtPath: path.path)
        log("start pid=\(ProcessInfo.processInfo.processIdentifier) log=\(path.path)")
        log("app active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(prefix) \(timestamp()) \(message())\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle {
            handle.write(data)
        } else {
            FileHandle.standardError.write(data)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    /// Prefers `<worktree>/work/overlay-diagnostic.log` when the app runs from
    /// the build tree; falls back to `~/Library/Logs/Framelet`.
    private static func logURL() -> URL {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--diag-log"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1])
        }
        if let env = ProcessInfo.processInfo.environment["FRAMELET_DIAG_LOG"] {
            return URL(fileURLWithPath: env)
        }
        let bundle = Bundle.main.bundleURL // .../dist/Framelet.app
        let work = bundle.deletingLastPathComponent().deletingLastPathComponent()
        let candidate = work.appendingPathComponent("work")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.appendingPathComponent("overlay-diagnostic.log")
        }
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Framelet")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("overlay-diagnostic.log")
    }

    // MARK: Describers

    static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "window=nil" }
        return "window{title=\(window.title) frame=\(NSStringFromRect(window.frame)) "
            + "visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) "
            + "level=\(window.level.rawValue) alpha=\(window.alphaValue) opaque=\(window.isOpaque) "
            + "occlusion=\(window.occlusionState.contains(.visible) ? "visible" : "occluded") "
            + "canBecomeKey=\(window.canBecomeKey) screen=\(window.screen.map { NSStringFromRect($0.frame) } ?? "nil") "
            + "onActiveSpace=\(window.isOnActiveSpace) "
            + "collection=\(OverlayDiag.describe(window.collectionBehavior)) "
            + "contentLayout=\(NSStringFromRect(window.contentLayoutRect))}"
    }

    static func describe(_ view: NSView?) -> String {
        guard let view else { return "view=nil" }
        return "view{\(type(of: view)) frame=\(NSStringFromRect(view.frame)) bounds=\(NSStringFromRect(view.bounds)) "
            + "hidden=\(view.isHidden) alpha=\(view.alphaValue) inWindow=\(view.window != nil) "
            + "needsDisplay=\(view.needsDisplay) subviews=\(view.subviews.count)}"
    }

    static func describe(_ behavior: NSWindow.CollectionBehavior) -> String {
        var parts: [String] = []
        if behavior.contains(.canJoinAllSpaces) { parts.append("canJoinAllSpaces") }
        if behavior.contains(.moveToActiveSpace) { parts.append("moveToActiveSpace") }
        if behavior.contains(.fullScreenPrimary) { parts.append("fullScreenPrimary") }
        if behavior.contains(.fullScreenAuxiliary) { parts.append("fullScreenAuxiliary") }
        if behavior.contains(.canJoinAllApplications) { parts.append("canJoinAllApplications") }
        if behavior.contains(.stationary) { parts.append("stationary") }
        if behavior.contains(.ignoresCycle) { parts.append("ignoresCycle") }
        return parts.isEmpty ? "none" : parts.joined(separator: "|")
    }

    static func firstResponder() -> String {
        guard let window = NSApp.keyWindow else { return "firstResponder{keyWindow=nil}" }
        let responder = window.firstResponder
        return "firstResponder{keyWindow=\(window.title) class=\(responder.map { String(describing: type(of: $0)) } ?? "nil")}"
    }
}
