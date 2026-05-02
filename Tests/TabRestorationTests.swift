import Foundation
@testable import MDViewer
import Testing

@MainActor
struct TabRestorationSuite {
    @Test func restoredPathsReadsFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        defaults.set(["/tmp/a.md", "/tmp/b.md"], forKey: SettingsKey.restoreTabs)

        let fm = StubFileManager(existing: ["/tmp/a.md", "/tmp/b.md"])
        let paths = TabRestoration.restoredPaths(defaults: defaults, fileExists: fm.exists)
        #expect(paths == ["/tmp/a.md", "/tmp/b.md"])
    }

    @Test func restoredPathsFiltersNonexistent() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        defaults.set(["/tmp/a.md", "/tmp/missing.md", "/tmp/b.md"], forKey: SettingsKey.restoreTabs)

        let fm = StubFileManager(existing: ["/tmp/a.md", "/tmp/b.md"])
        let paths = TabRestoration.restoredPaths(defaults: defaults, fileExists: fm.exists)
        #expect(paths == ["/tmp/a.md", "/tmp/b.md"])
    }

    @Test func restoredPathsEmptyWhenNoData() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        let fm = StubFileManager(existing: [])
        let paths = TabRestoration.restoredPaths(defaults: defaults, fileExists: fm.exists)
        #expect(paths.isEmpty)
    }

    @Test func recordWritesPaths() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        TabRestoration.record(paths: ["/tmp/a.md", "/tmp/b.md"], defaults: defaults)
        #expect(defaults.stringArray(forKey: SettingsKey.restoreTabs) == ["/tmp/a.md", "/tmp/b.md"])
    }

    /// Default `fileExists` predicate must reject directories so a saved
    /// path that's been replaced by a folder doesn't get handed to the
    /// markdown opener (which would surface a confusing system error).
    @Test func defaultPredicateRejectsDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tab-restore-\(UUID())")
        let file = dir.appendingPathComponent("file.md")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID())"))
        defaults.set([file.path, dir.path], forKey: SettingsKey.restoreTabs)

        // Use the production default (no injected closure).
        let paths = TabRestoration.restoredPaths(defaults: defaults)
        #expect(paths == [file.path], "directory must be filtered out, regular file kept")
    }
}

private struct StubFileManager {
    let existing: Set<String>
    init(existing: [String]) {
        self.existing = Set(existing)
    }

    func exists(_ path: String) -> Bool {
        existing.contains(path)
    }
}
