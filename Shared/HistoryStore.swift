import Foundation

@MainActor
@Observable
final class HistoryStore {
    static let maxEntries = 500

    private(set) var entries: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.stringArray(forKey: SettingsKey.history) ?? []
    }

    func recordOpen(_ url: URL) {
        let path = url.path
        entries.removeAll { $0 == path }
        entries.insert(path, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(_ path: String) {
        entries.removeAll { $0 == path }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func filtered(query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.range(of: q, options: .caseInsensitive) != nil }
    }

    private func persist() {
        defaults.set(entries, forKey: SettingsKey.history)
    }
}
