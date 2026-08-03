import Foundation

/// Persists a small list of recently saved screenshot files.
enum RecentScreenshots {
    private static let key = "recentScreenshots"
    private static let maxCount = 12

    static func add(_ url: URL) {
        var list = paths()
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func paths() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Existing files only, newest first.
    static func urls() -> [URL] {
        paths().map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
