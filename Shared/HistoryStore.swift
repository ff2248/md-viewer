import Foundation

@MainActor
@Observable
final class HistoryStore {
    static let maxEntries = 500

    private(set) var entries: [String]
    private var titles: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.stringArray(forKey: SettingsKey.history) ?? []
        titles = defaults.dictionary(forKey: SettingsKey.historyTitles) as? [String: String] ?? [:]
    }

    func recordOpen(_ url: URL, title: String? = nil) {
        let path = url.path
        entries.removeAll { $0 == path }
        entries.insert(path, at: 0)
        if let title, !title.isEmpty {
            titles[path] = title
        }
        if entries.count > Self.maxEntries {
            for stale in entries.dropFirst(Self.maxEntries) {
                titles.removeValue(forKey: stale)
            }
            entries = Array(entries.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(_ path: String) {
        entries.removeAll { $0 == path }
        titles.removeValue(forKey: path)
        persist()
    }

    func clear() {
        entries.removeAll()
        titles.removeAll()
        persist()
    }

    func filtered(query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { path in
            path.range(of: q, options: .caseInsensitive) != nil
                || titles[path]?.range(of: q, options: .caseInsensitive) != nil
        }
    }

    func title(for path: String) -> String? {
        titles[path]
    }

    private func persist() {
        defaults.set(entries, forKey: SettingsKey.history)
        defaults.set(titles, forKey: SettingsKey.historyTitles)
    }
}
