import Foundation

/// Persistent user-selected directory access for sandboxed and direct builds.
public enum SaveDirectoryAccess {
    public enum AccessError: LocalizedError {
        case invalidBookmark, accessDenied
        public var errorDescription: String? {
            switch self {
            case .invalidBookmark: return "保存位置已失效，请在设置中重新选择文件夹。"
            case .accessDenied: return "没有保存文件夹的访问权限，请在设置中重新选择。"
            }
        }
    }

    public static func bookmark(for directory: URL) throws -> Data {
        try directory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The callback runs while the scoped permission is active. A refreshed
    /// bookmark is provided when macOS reports that the stored one is stale.
    public static func withAccess<T>(bookmark: Data?, fallback: URL, _ body: (URL, Data?) throws -> T) throws -> T {
        guard let bookmark else { return try body(fallback, nil) }
        var stale = false
        let directory: URL
        do {
            directory = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch { throw AccessError.invalidBookmark }
        guard directory.startAccessingSecurityScopedResource() else { throw AccessError.accessDenied }
        defer { directory.stopAccessingSecurityScopedResource() }
        let refreshed = stale ? try self.bookmark(for: directory) : nil
        return try body(directory, refreshed)
    }
}
