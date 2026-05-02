import Foundation

enum TabRestoration {
    /// Persists the given file paths to be restored on next launch.
    static func record(paths: [String], defaults: UserDefaults = .standard) {
        defaults.set(paths, forKey: SettingsKey.restoreTabs)
    }

    /// Returns the saved paths, filtered down to regular files that
    /// still exist on disk. Directories at a recorded path (e.g. file
    /// replaced by a folder of the same name) are dropped so the
    /// restore loop doesn't hand a folder to the markdown opener.
    /// `fileExists` is injectable for tests.
    static func restoredPaths(
        defaults: UserDefaults = .standard,
        fileExists: (String) -> Bool = { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
        }
    ) -> [String] {
        let saved = defaults.stringArray(forKey: SettingsKey.restoreTabs) ?? []
        return saved.filter(fileExists)
    }
}
