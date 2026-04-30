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
        let editorPath = UserDefaults.standard.string(forKey: SettingsKey.externalEditor) ?? RenderOptions.defaultExternalEditor
        let editorURL = URL(filePath: editorPath)
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
