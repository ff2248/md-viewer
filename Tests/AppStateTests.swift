import AppKit
import Foundation
@testable import MDViewer
import Testing

struct AppStateSuite {
    // MARK: - Zoom

    @Test @MainActor func zoomInIncreasesFontSize() {
        let state = AppState()
        state.bodyFontSize = 18
        state.zoomIn()
        #expect(state.bodyFontSize == 19)
    }

    @Test @MainActor func zoomInClampsToMax() {
        let state = AppState()
        state.bodyFontSize = RenderOptions.bodyFontSizeRange.upperBound
        state.zoomIn()
        #expect(state.bodyFontSize == RenderOptions.bodyFontSizeRange.upperBound)
    }

    @Test @MainActor func zoomOutDecreasesFontSize() {
        let state = AppState()
        state.bodyFontSize = 18 // set explicitly to avoid UserDefaults interference
        state.zoomOut()
        #expect(state.bodyFontSize == 17)
    }

    @Test @MainActor func zoomOutClampsToMin() {
        let state = AppState()
        state.bodyFontSize = RenderOptions.bodyFontSizeRange.lowerBound
        state.zoomOut()
        #expect(state.bodyFontSize == RenderOptions.bodyFontSizeRange.lowerBound)
    }

    @Test @MainActor func resetZoomRestoresDefault() {
        let state = AppState()
        state.bodyFontSize = 20
        state.resetZoom()
        #expect(state.bodyFontSize == RenderOptions.defaults.bodyFontSize)
    }

    // MARK: - renderOptions

    @Test @MainActor func renderOptionsReflectsState() {
        let state = AppState()
        state.hardBreaks = false
        state.showFrontMatter = false
        state.bodyFontSize = 20
        state.codeFontSize = 15
        let opts = state.renderOptions
        #expect(opts.hardBreaks == false)
        #expect(opts.showFrontMatter == false)
        #expect(opts.bodyFontSize == 20)
        #expect(opts.codeFontSize == 15)
    }

    // MARK: - openFile

    @Test @MainActor func openFileSuccess() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).md")
        try "# Hello".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let state = AppState()
        state.openFile(tempFile)
        #expect(state.markdown == "# Hello")
        #expect(state.fileURL == tempFile)
        #expect(state.windowTitle == tempFile.lastPathComponent)
    }

    @Test @MainActor func openFileFailure() {
        let state = AppState()
        state.markdown = "existing"
        state.openFile(URL(fileURLWithPath: "/nonexistent.md"))
        #expect(state.markdown.isEmpty)
        #expect(state.fileURL == nil)
        #expect(state.windowTitle == "MDViewer")
    }

    // MARK: - applyAppearance

    @Test @MainActor func applyAppearanceLight() {
        AppState.applyAppearance("light")
        #expect(NSApp?.appearance?.name == .aqua)
    }

    @Test @MainActor func applyAppearanceDark() {
        AppState.applyAppearance("dark")
        #expect(NSApp?.appearance?.name == .darkAqua)
    }

    @Test @MainActor func applyAppearanceAuto() {
        AppState.applyAppearance("auto")
        #expect(NSApp?.appearance == nil)
    }
}
