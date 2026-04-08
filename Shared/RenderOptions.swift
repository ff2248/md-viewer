import Foundation

/// Shared rendering options used across the app and Quick Look extension.
struct RenderOptions: Equatable {
    var hardBreaks: Bool
    var showFrontMatter: Bool
    var bodyFontSize: Double
    var codeFontSize: Double

    static let defaults = RenderOptions(
        hardBreaks: true,
        showFrontMatter: true,
        bodyFontSize: 16,
        codeFontSize: 13
    )

    /// Load from UserDefaults, falling back to defaults for unset keys.
    static func fromDefaults(_ d: UserDefaults = .standard) -> RenderOptions {
        RenderOptions(
            hardBreaks: d.object(forKey: "hardBreaks") == nil || d.bool(forKey: "hardBreaks"),
            showFrontMatter: d.object(forKey: "showFrontMatter") == nil || d.bool(forKey: "showFrontMatter"),
            bodyFontSize: { let v = d.double(forKey: "bodyFontSize"); return v > 0 ? v : defaults.bodyFontSize }(),
            codeFontSize: { let v = d.double(forKey: "codeFontSize"); return v > 0 ? v : defaults.codeFontSize }()
        )
    }
}
