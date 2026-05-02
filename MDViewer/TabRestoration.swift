import Foundation

enum TabRestoration {
    /// Persists the given file paths to be restored on next launch.
    static func record(paths: [String], defaults: UserDefaults = .standard) {
        defaults.set(paths, forKey: SettingsKey.restoreTabs)
    }

    /// Returns the saved paths, filtered down to those that still exist on disk.
    /// `fileExists` is injectable for tests; production callers can pass `FileManager.default.fileExists(atPath:)`.
    static func restoredPaths(
        defaults: UserDefaults = .standard,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        let saved = defaults.stringArray(forKey: SettingsKey.restoreTabs) ?? []
        return saved.filter(fileExists)
    }
}
