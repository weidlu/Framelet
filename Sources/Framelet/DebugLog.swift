import Foundation
import AppKit
import OSLog

/// Opt-in file log for local acceptance runs. Enabled with `--debug-log <path>`
/// or the FRAMELET_DEBUG_LOG environment variable; a no-op in normal use.
enum DebugLog {
    private static var handle: FileHandle?

    static func configure() {
        let args = ProcessInfo.processInfo.arguments
        var path = ProcessInfo.processInfo.environment["FRAMELET_DEBUG_LOG"]
        if let index = args.firstIndex(of: "--debug-log"), args.indices.contains(index + 1) {
            path = args[index + 1]
        }
        guard let path else { return }
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    static func write(_ message: String) {
        guard let handle else { return }
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) { handle.write(data) }
    }
}

/// Error-only, bounded log. No pixels, OCR text, window titles or keystrokes.
/// Disables just the optional dimension label for the rest of this process.
enum CaptureRecoveryLog {
    private(set) static var labelDisabled = false
    private static var noticePending = false
    private(set) static var persistenceError: String?
    private static let logger = Logger(subsystem: "com.framelet.capture", category: "CaptureRecovery")
    static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Framelet/capture-errors.log")
    }

    static func disableLabel(_ error: NSError?) {
        guard !labelDisabled else { return }
        labelDisabled = true
        noticePending = true
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        let message = "[\(Date())] dimension-label-disabled version=\(version) build=\(build) os=\(ProcessInfo.processInfo.operatingSystemVersionString)\n\(error?.description ?? "Unknown text rendering failure")\n"
        logger.error("\(message, privacy: .public)")
        do {
            let url = logURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = (try? Data(contentsOf: url)) ?? Data()
            if data.count > 128 * 1024 { data = Data() }
            data.append(Data(message.utf8))
            try data.write(to: url, options: .atomic)
        } catch {
            persistenceError = error.localizedDescription
            logger.error("Cannot persist capture recovery log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called only after the selection session ends, so no modal interrupts capture.
    static func showPendingNotice() {
        guard noticePending else { return }
        noticePending = false
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "截图尺寸提示已临时隐藏"
            alert.informativeText = "显示尺寸文字时出现异常，已关闭本次运行的尺寸提示。选区、标注和保存功能可继续使用。你可以从菜单栏的“查看截图错误记录…”找到报障信息。"
            alert.addButton(withTitle: "知道了")
            alert.addButton(withTitle: "查看错误记录")
            if alert.runModal() == .alertSecondButtonReturn { reveal() }
        }
    }

    static func reveal() {
        guard FileManager.default.fileExists(atPath: logURL.path), persistenceError == nil else {
            let alert = NSAlert()
            alert.messageText = labelDisabled ? "错误记录未能保存" : "尚无截图错误记录"
            alert.informativeText = persistenceError ?? "尚未记录到尺寸提示异常。若应用直接退出，macOS 崩溃报告位于“控制台”中的崩溃报告列表。"
            alert.runModal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }
}
