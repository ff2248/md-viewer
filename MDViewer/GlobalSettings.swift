import AppKit
import Foundation

@MainActor
@Observable
class GlobalSettings {
    var showSettings = false
    var hardBreaks: Bool = RenderOptions.defaults.hardBreaks
    var showFrontMatter: Bool = RenderOptions.defaults.showFrontMatter
    var bodyFontSize: Double = RenderOptions.defaults.bodyFontSize
    var codeFontSize: Double = RenderOptions.defaults.codeFontSize

    var renderOptions: RenderOptions {
        RenderOptions(hardBreaks: hardBreaks, showFrontMatter: showFrontMatter,
                      bodyFontSize: bodyFontSize, codeFontSize: codeFontSize)
    }

    private let defaults: UserDefaults
    private nonisolated(unsafe) var defaultsObserver: Any?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        syncFromDefaults()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.syncFromDefaults() } }
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func syncFromDefaults() {
        let opts = RenderOptions.fromDefaults(defaults)
        hardBreaks = opts.hardBreaks
        showFrontMatter = opts.showFrontMatter
        bodyFontSize = opts.bodyFontSize
        codeFontSize = opts.codeFontSize
    }

    static func applyAppearance(_ value: String) {
        guard let app = NSApp else { return }
        switch value {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        bodyFontSize = min(bodyFontSize + 1, RenderOptions.bodyFontSizeRange.upperBound)
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func zoomOut() {
        bodyFontSize = max(bodyFontSize - 1, RenderOptions.bodyFontSizeRange.lowerBound)
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func resetZoom() {
        bodyFontSize = RenderOptions.defaults.bodyFontSize
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    // MARK: - External Editor

    static func openInExternalEditor(url: URL) {
        var editorPath = UserDefaults.standard.string(forKey: SettingsKey.externalEditor) ?? RenderOptions.defaultExternalEditor
        // Belt-and-suspenders: launch validation in AppDelegate handles
        // cross-session uninstalls; this catches the rare in-session case
        // where the user removes the editor between launching MDViewer
        // and pressing ⇧⌘E.
        if !FileManager.default.fileExists(atPath: editorPath) {
            editorPath = detectDefaultExternalEditor()
            UserDefaults.standard.set(editorPath, forKey: SettingsKey.externalEditor)
        }
        let editorURL = URL(filePath: editorPath)
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Editor entry shown in the Settings picker — the bundle ID is
    /// recovered from `RenderOptions.recommendedExternalEditors` and the
    /// path resolved via Launch Services at query time.
    struct RecommendedEditor: Hashable {
        let path: String
        let displayName: String
    }

    /// Recommended editors that are actually installed on this machine,
    /// in the order declared by `RenderOptions.recommendedExternalEditors`.
    /// The Settings picker reads this; first-launch default uses the
    /// first entry.
    static func installedRecommendedEditors() -> [RecommendedEditor] {
        RenderOptions.recommendedExternalEditors.compactMap { entry in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else { return nil }
            return RecommendedEditor(path: url.path, displayName: entry.displayName)
        }
    }

    /// Path of the first recommended editor that's installed, or the
    /// hardcoded TextEdit fallback if somehow none of the curated apps
    /// are present (TextEdit ships with macOS, so this is rare).
    static func detectDefaultExternalEditor() -> String {
        installedRecommendedEditors().first?.path ?? RenderOptions.defaultExternalEditor
    }
}
