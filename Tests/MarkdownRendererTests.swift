import Foundation
@testable import MDViewer
import Testing

/// Helper to build RenderOptions with specific overrides from defaults.
private func options(hardBreaks: Bool = RenderOptions.defaults.hardBreaks,
                     showFrontMatter: Bool = RenderOptions.defaults.showFrontMatter) -> RenderOptions
{
    RenderOptions(hardBreaks: hardBreaks, showFrontMatter: showFrontMatter,
                  bodyFontSize: RenderOptions.defaults.bodyFontSize,
                  codeFontSize: RenderOptions.defaults.codeFontSize)
}

/// Bundle for tests that need bundled resources.
private let testBundle = Bundle(identifier: "com.local.MDViewer") ?? .main

// MARK: - MarkdownRenderer

struct MarkdownRendererSuite {
    @Test func errorHTMLContainsMessage() {
        let html = MarkdownRenderer.errorHTML(message: "File not found")
        #expect(html.contains("File not found"))
    }

    @Test func errorHTMLEscapesHTML() {
        let html = MarkdownRenderer.errorHTML(message: "<script>alert('xss')</script>")
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script"))
    }

    @Test func readFileSuccess() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).md")
        try "# Test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        #expect(try MarkdownRenderer.readMarkdownFile(at: tempFile).get() == "# Test")
    }

    @Test func readFileFailure() {
        let result = MarkdownRenderer.readMarkdownFile(at: URL(fileURLWithPath: "/nonexistent.md"))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test func hasMermaidDetectsBlock() {
        #expect(MarkdownRenderer.hasMermaid("```mermaid\ngraph TD\n```"))
    }

    @Test func hasMermaidReturnsFalseForNormal() {
        #expect(!MarkdownRenderer.hasMermaid("# Hello\nNo mermaid here"))
    }

    @Test func selfContainedHTMLContainsRenderedContent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# Hello", bundle: testBundle)
        #expect(html.contains("<h1>"))
        #expect(html.contains("Hello"))
        #expect(html.contains("markdown-body"))
    }

    @Test func selfContainedHTMLContainsCSS() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "test", bundle: testBundle)
        #expect(html.contains("<style>"))
    }

    @Test func selfContainedHTMLIncludesMermaidWhenPresent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "```mermaid\ngraph TD\n```", bundle: testBundle)
        #expect(html.contains("mermaid"))
    }

    @Test func selfContainedHTMLExcludesMermaidWhenAbsent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# No mermaid", bundle: testBundle)
        #expect(!html.contains("mermaid.initialize"))
    }
}

// MARK: - MarkdownParser

struct MarkdownParserSuite {
    @Test func rendersHeading() {
        let html = MarkdownParser.toHTML("# Hello")
        #expect(html.contains("<h1>"))
        #expect(html.contains("Hello"))
    }

    @Test func rendersGFMTable() {
        let html = MarkdownParser.toHTML("| A | B |\n|---|---|\n| 1 | 2 |")
        #expect(html.contains("<table>"))
        #expect(html.contains("<td>"))
    }

    @Test func rendersTaskList() {
        let html = MarkdownParser.toHTML("- [x] Done\n- [ ] Todo")
        #expect(html.contains("checked"))
        #expect(html.contains("checkbox"))
    }

    // Note: strikethrough, footnotes, and autolinks require cmark-gfm extensions
    // which may not load in the test target. Tested manually.

    @Test func tagFilterBlocksDangerousTags() {
        #expect(!MarkdownParser.toHTML("<script>alert(1)</script>").contains("<script>"))
    }

    @Test func tagFilterAllowsSafeTags() {
        #expect(MarkdownParser.toHTML("<details><summary>click</summary>hi</details>").contains("<details>"))
    }

    @Test func rawHTMLIsRendered() {
        #expect(MarkdownParser.toHTML("<div>hello</div>").contains("<div>hello</div>"))
    }

    @Test func emptyStringReturnsEmpty() {
        #expect(MarkdownParser.toHTML("").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func mathCodeBlockProducesLanguageMathClass() {
        #expect(MarkdownParser.toHTML("```math\nE = mc^2\n```").contains("language-math"))
    }
}

// MARK: - Hard Breaks

struct HardBreaksSuite {
    @Test func enabled() {
        #expect(MarkdownParser.toHTML("line1\nline2", options: options(hardBreaks: true)).contains("<br"))
    }

    @Test func disabled() {
        #expect(!MarkdownParser.toHTML("line1\nline2", options: options(hardBreaks: false)).contains("<br"))
    }
}

// MARK: - Front Matter

struct FrontMatterSuite {
    @Test func strippedByDefault() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\n---\n# Hello")
        #expect(html.contains("<h1>"))
        #expect(!html.contains("title: Test"))
    }

    @Test func renderedAsTable() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\nauthor: Alice\n---\n# Hello",
                                         options: options(showFrontMatter: true))
        #expect(html.contains("<table>"))
        #expect(html.contains("title"))
        #expect(html.contains("Alice"))
    }

    @Test func hiddenWhenDisabled() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\n---\n# Hello",
                                         options: options(showFrontMatter: false))
        #expect(!html.contains("<table>"))
        #expect(html.contains("<h1>"))
    }

    @Test func preservedWithoutFrontMatter() {
        #expect(MarkdownParser.toHTML("# No front matter").contains("No front matter"))
    }

    @Test func malformedPreserved() {
        #expect(MarkdownParser.toHTML("---\nno closing\n# Hello").contains("Hello"))
    }

    @Test func emptyValue() throws {
        var text = "---\nkey:\n---\nContent"
        let table = MarkdownParser.extractFrontMatter(&text)
        #expect(try #require(table).contains("key"))
    }

    @Test func onlyDelimiters() {
        var text = "---\n---\nContent"
        #expect(MarkdownParser.extractFrontMatter(&text) == nil)
        #expect(text.contains("Content"))
    }
}

// MARK: - Emoji

struct EmojiSuite {
    @Test func singleReplacement() {
        let html = MarkdownParser.toHTML(":rocket: launch!")
        #expect(html.contains("🚀"))
        #expect(!html.contains(":rocket:"))
    }

    @Test func multipleReplacements() {
        let html = MarkdownParser.toHTML(":heart: :star: :fire:")
        #expect(html.contains("❤️"))
        #expect(html.contains("⭐"))
        #expect(html.contains("🔥"))
    }

    @Test func unknownUnchanged() {
        #expect(MarkdownParser.toHTML(":nonexistent_emoji:").contains(":nonexistent_emoji:"))
    }

    @Test func replacedEvenInInlineCode() {
        // Known behavior: emoji replacement runs before cmark-gfm parsing
        #expect(MarkdownParser.toHTML("`code :rocket: here`").contains("🚀"))
    }
}

// MARK: - StringExtensions

struct StringExtensionsSuite {
    @Test(arguments: [
        ("a\\b", "a\\\\b"),
        ("it's", "it\\'s"),
        ("a\nb", "a\\nb"),
        ("a\rb", "a\\rb"),
        ("line1\nit's a\\path", "line1\\nit\\'s a\\\\path"),
        ("", ""),
    ])
    func jsEscaped(input: String, expected: String) {
        #expect(input.jsEscaped == expected)
    }

    @Test func htmlUnescaped() {
        #expect("&amp; &lt; &gt; &quot; &#39;".htmlUnescaped == "& < > \" '")
        #expect("".htmlUnescaped == "")
    }

    @Test func htmlEscaped() {
        #expect("& < > \"".htmlEscaped == "&amp; &lt; &gt; &quot;")
        #expect("".htmlEscaped == "")
    }
}

// MARK: - RenderOptions

struct RenderOptionsSuite {
    @Test func defaults() {
        let d = RenderOptions.defaults
        #expect(d.hardBreaks)
        #expect(d.showFrontMatter)
        #expect(d.bodyFontSize == 16)
        #expect(d.codeFontSize == 13)
    }

    @Test func equatable() {
        #expect(RenderOptions.defaults == options())
        #expect(RenderOptions.defaults != options(hardBreaks: false))
    }

    @Test func fontSizeRanges() {
        #expect(RenderOptions.bodyFontSizeRange == 12 ... 24)
        #expect(RenderOptions.codeFontSizeRange == 10 ... 20)
    }

    @Test func markdownExtensions() {
        #expect(RenderOptions.markdownExtensions.contains("md"))
        #expect(RenderOptions.markdownExtensions.contains("markdown"))
        #expect(!RenderOptions.markdownExtensions.contains("txt"))
    }

    @Test func fromDefaultsEmpty() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-empty-\(UUID())"))
        #expect(RenderOptions.fromDefaults(defaults) == RenderOptions.defaults)
    }

    @Test func fromDefaultsCustom() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-custom-\(UUID())"))
        defaults.set(false, forKey: SettingsKey.hardBreaks)
        defaults.set(20.0, forKey: SettingsKey.bodyFontSize)
        let opts = RenderOptions.fromDefaults(defaults)
        #expect(!opts.hardBreaks)
        #expect(opts.bodyFontSize == 20)
    }
}

// MARK: - inlineLocalImages

struct InlineLocalImagesSuite {
    private static let baseURL = URL(fileURLWithPath: "/tmp/test.md")

    @Test func skipsHttpUrls() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"https://example.com/img.png\">", relativeTo: Self.baseURL)
        #expect(result.contains("https://example.com/img.png"))
        #expect(!result.contains("data:"))
    }

    @Test func skipsDataUrls() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"data:image/png;base64,abc\">", relativeTo: Self.baseURL)
        #expect(result.contains("data:image/png"))
    }

    @Test func preservesNonexistentFile() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"nonexistent.png\">", relativeTo: Self.baseURL)
        #expect(result.contains("nonexistent.png"))
        #expect(!result.contains("base64"))
    }
}
