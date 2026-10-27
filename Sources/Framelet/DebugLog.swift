import Foundation

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
