import Foundation
@testable import MDViewer
import Testing

@MainActor
struct HistoryStoreSuite {
    private static func makeStore() -> HistoryStore {
        HistoryStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    }

    @Test func recordOpenAddsToFront() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.recordOpen(URL(filePath: "/tmp/b.md"))
        #expect(store.entries == ["/tmp/b.md", "/tmp/a.md"])
    }

    @Test func recordOpenDedupesAndMovesToFront() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.recordOpen(URL(filePath: "/tmp/b.md"))
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        #expect(store.entries == ["/tmp/a.md", "/tmp/b.md"])
    }

    @Test func recordOpenTrimsToMaxEntries() {
        let store = Self.makeStore()
        for i in 0 ..< (HistoryStore.maxEntries + 10) {
            store.recordOpen(URL(filePath: "/tmp/file\(i).md"))
        }
        #expect(store.entries.count == HistoryStore.maxEntries)
        #expect(store.entries.first == "/tmp/file\(HistoryStore.maxEntries + 9).md")
        #expect(store.entries.last == "/tmp/file10.md")
    }

    @Test func removeRemovesPath() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.recordOpen(URL(filePath: "/tmp/b.md"))
        store.remove("/tmp/a.md")
        #expect(store.entries == ["/tmp/b.md"])
    }

    @Test func removeNonexistentIsNoop() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.remove("/tmp/zzz.md")
        #expect(store.entries == ["/tmp/a.md"])
    }

    @Test func clearEmptiesEntries() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.recordOpen(URL(filePath: "/tmp/b.md"))
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test func filteredEmptyQueryReturnsAll() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"))
        store.recordOpen(URL(filePath: "/tmp/b.md"))
        #expect(store.filtered(query: "") == ["/tmp/b.md", "/tmp/a.md"])
        #expect(store.filtered(query: "   ") == ["/tmp/b.md", "/tmp/a.md"])
    }

    @Test func filteredMatchesFilename() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/notes.md"))
        store.recordOpen(URL(filePath: "/tmp/other/spec.md"))
        #expect(store.filtered(query: "notes") == ["/tmp/notes.md"])
    }

    @Test func filteredMatchesPathSegment() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/Users/me/work/notes.md"))
        store.recordOpen(URL(filePath: "/tmp/other.md"))
        #expect(store.filtered(query: "work") == ["/Users/me/work/notes.md"])
    }

    @Test func filteredCaseInsensitive() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/NOTES.md"))
        #expect(store.filtered(query: "notes") == ["/tmp/NOTES.md"])
    }

    @Test func persistsAcrossInstances() throws {
        let suite = "test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let first = HistoryStore(defaults: defaults)
        first.recordOpen(URL(filePath: "/tmp/a.md"))
        first.recordOpen(URL(filePath: "/tmp/b.md"))

        let second = HistoryStore(defaults: defaults)
        #expect(second.entries == ["/tmp/b.md", "/tmp/a.md"])
    }

    @Test func removeIsPersisted() throws {
        let suite = "test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let first = HistoryStore(defaults: defaults)
        first.recordOpen(URL(filePath: "/tmp/a.md"))
        first.remove("/tmp/a.md")

        let second = HistoryStore(defaults: defaults)
        #expect(second.entries.isEmpty)
    }

    @Test func clearIsPersisted() throws {
        let suite = "test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let first = HistoryStore(defaults: defaults)
        first.recordOpen(URL(filePath: "/tmp/a.md"))
        first.clear()

        let second = HistoryStore(defaults: defaults)
        #expect(second.entries.isEmpty)
    }

    @Test func titleStoredAndRetrieved() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/notes.md"), title: "My Notes")
        #expect(store.title(for: "/tmp/notes.md") == "My Notes")
        #expect(store.title(for: "/tmp/unknown.md") == nil)
    }

    @Test func nilTitleDoesNotOverwriteExisting() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"), title: "First")
        store.recordOpen(URL(filePath: "/tmp/a.md"), title: nil)
        #expect(store.title(for: "/tmp/a.md") == "First")
    }

    @Test func removeAlsoDropsTitle() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"), title: "Title")
        store.remove("/tmp/a.md")
        #expect(store.title(for: "/tmp/a.md") == nil)
    }

    @Test func clearAlsoDropsTitles() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"), title: "A")
        store.recordOpen(URL(filePath: "/tmp/b.md"), title: "B")
        store.clear()
        #expect(store.title(for: "/tmp/a.md") == nil)
        #expect(store.title(for: "/tmp/b.md") == nil)
    }

    @Test func filteredMatchesTitle() {
        let store = Self.makeStore()
        store.recordOpen(URL(filePath: "/tmp/a.md"), title: "Migration Plan")
        store.recordOpen(URL(filePath: "/tmp/b.md"), title: "Release Notes")
        #expect(store.filtered(query: "migration") == ["/tmp/a.md"])
    }

    @Test func trimsTitlesWhenTrimmingEntries() {
        let store = Self.makeStore()
        for i in 0 ..< (HistoryStore.maxEntries + 5) {
            store.recordOpen(URL(filePath: "/tmp/file\(i).md"), title: "Title \(i)")
        }
        #expect(store.title(for: "/tmp/file0.md") == nil)
        #expect(store.title(for: "/tmp/file\(HistoryStore.maxEntries + 4).md") == "Title \(HistoryStore.maxEntries + 4)")
    }

    @Test func titlesPersistAcrossInstances() throws {
        let suite = "test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let first = HistoryStore(defaults: defaults)
        first.recordOpen(URL(filePath: "/tmp/a.md"), title: "Hello")

        let second = HistoryStore(defaults: defaults)
        #expect(second.title(for: "/tmp/a.md") == "Hello")
    }
}
