import Foundation

/// Centralized SwiftUI Window scene identifiers.
enum WindowID {
    static let history = "history"
}

/// Centralized UserDefaults key names.
enum SettingsKey {
    static let appearance = "appearance"
    static let hardBreaks = "hardBreaks"
    static let showFrontMatter = "showFrontMatter"
    static let bodyFontSize = "bodyFontSize"
    static let codeFontSize = "codeFontSize"
    static let externalEditor = "externalEditor"
    static let restoreTabs = "restoreTabs"
    static let restoreTabsEnabled = "restoreTabsEnabled"
    static let history = "history"
}

/// Shared rendering options used across the app and Quick Look extension.
struct RenderOptions: Equatable {
    var hardBreaks: Bool
    var showFrontMatter: Bool
    var bodyFontSize: Double
    var codeFontSize: Double

    static let defaults = RenderOptions(
        hardBreaks: true,
        showFrontMatter: true,
        bodyFontSize: 15,
        codeFontSize: 12
    )

    static let bodyFontSizeRange: ClosedRange<Double> = 12 ... 24
    static let codeFontSizeRange: ClosedRange<Double> = 10 ... 20

    static let defaultExternalEditor = "/System/Applications/TextEdit.app"
    static let markdownExtensions = ["md", "markdown", "mdown", "mkd"]

    /// Curated list of editors offered as suggestions in Settings, in
    /// preference order. The list is intersected with what's actually
    /// installed at runtime. TextEdit is last so the final fallback is
    /// always something macOS ships with.
    static let recommendedExternalEditors: [(bundleID: String, displayName: String)] = [
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("md.obsidian", "Obsidian"),
        ("abnerworks.Typora", "Typora"),
        ("com.sublimetext.4", "Sublime Text"),
        ("com.coteditor.CotEditor", "CotEditor"),
        ("pro.writer.mac", "iA Writer"),
        ("com.barebones.bbedit", "BBEdit"),
        ("com.apple.TextEdit", "TextEdit"),
    ]

    /// Load from UserDefaults, falling back to defaults for unset keys.
    static func fromDefaults(_ d: UserDefaults = .standard) -> RenderOptions {
        RenderOptions(
            hardBreaks: d.object(forKey: SettingsKey.hardBreaks) == nil || d.bool(forKey: SettingsKey.hardBreaks),
            showFrontMatter: d.object(forKey: SettingsKey.showFrontMatter) == nil || d.bool(forKey: SettingsKey.showFrontMatter),
            bodyFontSize: { let v = d.double(forKey: SettingsKey.bodyFontSize); return v > 0 ? v : defaults.bodyFontSize }(),
            codeFontSize: { let v = d.double(forKey: SettingsKey.codeFontSize); return v > 0 ? v : defaults.codeFontSize }()
        )
    }
}

extension UserDefaults {
    static func registerMDViewerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.restoreTabsEnabled: true,
        ])
    }
}
