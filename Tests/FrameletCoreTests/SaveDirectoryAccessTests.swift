import Foundation
import FrameletCore

extension ImagingChecks {
    static func saveDirectoryBookmarkRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Framelet-save-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var settings = AppSettings.defaults
        settings.completionAction = .saveAndCopy
        settings.saveDirectoryPath = directory.path
        settings.saveDirectoryBookmark = try SaveDirectoryAccess.bookmark(for: directory)
        let restored = try unwrap(AppSettings.from(data: try unwrap(settings.encode())))
        try expect(restored.saveDirectoryBookmark == settings.saveDirectoryBookmark, "bookmark persists in settings")
        try expect(restored.completionAction == .saveAndCopy, "other settings survive")

        let fileName = "scope-check.txt"
        try SaveDirectoryAccess.withAccess(bookmark: restored.saveDirectoryBookmark, fallback: URL(fileURLWithPath: "/")) { resolved, _ in
            let file = resolved.appendingPathComponent(fileName)
            try Data("Framelet".utf8).write(to: file)
            try expect(Data(contentsOf: file) == Data("Framelet".utf8), "chosen folder is writable during scoped access")
        }

        var legacy = try unwrap(JSONSerialization.jsonObject(with: try unwrap(settings.encode())) as? [String: Any])
        legacy.removeValue(forKey: "saveDirectoryBookmark")
        let migrated = try unwrap(AppSettings.from(data: try JSONSerialization.data(withJSONObject: legacy)))
        try expect(migrated.saveDirectoryBookmark == nil && migrated.completionAction == .saveAndCopy, "legacy settings decode without losing preferences")
        try SaveDirectoryAccess.withAccess(bookmark: nil, fallback: directory) { fallback, _ in
            try expect(fallback == directory, "legacy non-bookmarked save location remains available")
        }
    }

    static func invalidSaveDirectoryBookmark() throws {
        var invoked = false
        do {
            try SaveDirectoryAccess.withAccess(bookmark: Data("invalid".utf8), fallback: FileManager.default.temporaryDirectory) { _, _ in
                invoked = true
            }
            throw Failure(description: "invalid bookmark must fail")
        } catch SaveDirectoryAccess.AccessError.invalidBookmark {
            try expect(!invoked, "invalid bookmarks must not silently fall back")
        }
    }
}
