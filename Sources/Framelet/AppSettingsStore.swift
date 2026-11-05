import AppKit
import Combine
import FrameletCore

/// Owns the typed settings model and persists it to `UserDefaults`. Any damage
/// or unknown value falls back to safe defaults with a notice instead of
/// crashing at launch.
@MainActor final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings { didSet { persist() } }
    @Published var repairNotice: String?
    private let defaults: UserDefaults
    private let key = "framelet.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                let repaired = decoded.repaired
                if repaired != decoded {
                    repairNotice = "检测到部分设置无效，已恢复为安全默认值。"
                }
                settings = repaired
            } else {
                repairNotice = "设置数据无法读取，已恢复默认值。"
                settings = .defaults
            }
        } else {
            settings = .defaults
        }
    }

    func resetAll() {
        settings = .defaults
        repairNotice = nil
    }

    private func persist() {
        if let data = settings.encode() {
            defaults.set(data, forKey: key)
        }
    }

    /// Resolves the expanded save directory path.
    var saveDirectoryURL: URL {
        let expanded = (settings.saveDirectoryPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    func selectSaveDirectory(_ directory: URL) throws {
        let bookmark = try SaveDirectoryAccess.bookmark(for: directory)
        var updated = settings
        updated.saveDirectoryPath = directory.path
        updated.saveDirectoryBookmark = bookmark
        settings = updated
    }

    func withSaveDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        try SaveDirectoryAccess.withAccess(bookmark: settings.saveDirectoryBookmark, fallback: saveDirectoryURL) { directory, refreshed in
            if refreshed != nil || directory.path != settings.saveDirectoryPath {
                var updated = settings
                updated.saveDirectoryPath = directory.path
                if let refreshed { updated.saveDirectoryBookmark = refreshed }
                settings = updated
            }
            return try body(directory)
        }
    }
}
