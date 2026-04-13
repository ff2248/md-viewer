import AppKit
@testable import MDViewer
import Testing

struct GlobalSettingsSuite {
    /// Isolated UserDefaults for each test — never touches the real app preferences.
    @MainActor private static func makeSettings() -> GlobalSettings {
        GlobalSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    }

    // MARK: - Zoom

    @Test @MainActor func zoomInIncreasesFontSize() {
        let settings = Self.makeSettings()
        settings.bodyFontSize = 18
        settings.zoomIn()
        #expect(settings.bodyFontSize == 19)
    }

    @Test @MainActor func zoomInClampsToMax() {
        let settings = Self.makeSettings()
        settings.bodyFontSize = RenderOptions.bodyFontSizeRange.upperBound
        settings.zoomIn()
        #expect(settings.bodyFontSize == RenderOptions.bodyFontSizeRange.upperBound)
    }

    @Test @MainActor func zoomOutDecreasesFontSize() {
        let settings = Self.makeSettings()
        settings.bodyFontSize = 18
        settings.zoomOut()
        #expect(settings.bodyFontSize == 17)
    }

    @Test @MainActor func zoomOutClampsToMin() {
        let settings = Self.makeSettings()
        settings.bodyFontSize = RenderOptions.bodyFontSizeRange.lowerBound
        settings.zoomOut()
        #expect(settings.bodyFontSize == RenderOptions.bodyFontSizeRange.lowerBound)
    }

    @Test @MainActor func resetZoomRestoresDefault() {
        let settings = Self.makeSettings()
        settings.bodyFontSize = 20
        settings.resetZoom()
        #expect(settings.bodyFontSize == RenderOptions.defaults.bodyFontSize)
    }

    // MARK: - renderOptions

    @Test @MainActor func renderOptionsReflectsState() {
        let settings = Self.makeSettings()
        settings.hardBreaks = false
        settings.showFrontMatter = false
        settings.bodyFontSize = 20
        settings.codeFontSize = 15
        let opts = settings.renderOptions
        #expect(opts.hardBreaks == false)
        #expect(opts.showFrontMatter == false)
        #expect(opts.bodyFontSize == 20)
        #expect(opts.codeFontSize == 15)
    }

    // MARK: - applyAppearance

    @Test @MainActor func applyAppearanceLight() {
        GlobalSettings.applyAppearance("light")
        #expect(NSApp?.appearance?.name == .aqua)
    }

    @Test @MainActor func applyAppearanceDark() {
        GlobalSettings.applyAppearance("dark")
        #expect(NSApp?.appearance?.name == .darkAqua)
    }

    @Test @MainActor func applyAppearanceAuto() {
        GlobalSettings.applyAppearance("auto")
        #expect(NSApp?.appearance == nil)
    }
}

struct MarkdownDocumentSuite {
    @Test func initWithText() {
        let doc = MarkdownDocument(text: "# Hello")
        #expect(doc.text == "# Hello")
    }

    @Test func initEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text.isEmpty)
    }

    @Test func readableContentTypes() {
        #expect(!MarkdownDocument.readableContentTypes.isEmpty)
    }
}
