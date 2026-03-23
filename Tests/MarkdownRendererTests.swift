import XCTest
@testable import MDViewer

final class MarkdownRendererTests: XCTestCase {

    // MARK: - errorHTML

    func testErrorHTMLContainsMessage() {
        let html = MarkdownRenderer.errorHTML(message: "File not found")
        XCTAssertTrue(html.contains("File not found"))
    }

    func testErrorHTMLEscapesHTML() {
        let html = MarkdownRenderer.errorHTML(message: "<script>alert('xss')</script>")
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script"))
    }

    // MARK: - readMarkdownFile

    func testReadFileSuccess() {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test.md")
        try? "# Test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        if case .success(let text) = MarkdownRenderer.readMarkdownFile(at: tempFile) {
            XCTAssertEqual(text, "# Test")
        } else {
            XCTFail("Expected success")
        }
    }

    func testReadFileFailure() {
        let result = MarkdownRenderer.readMarkdownFile(at: URL(fileURLWithPath: "/nonexistent.md"))
        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - MarkdownParser (cmark-gfm)

    func testParserRendersHeading() {
        let html = MarkdownParser.toHTML("# Hello")
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("Hello"))
    }

    func testParserRendersGFMTable() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = MarkdownParser.toHTML(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<td>"))
    }

    func testParserRendersTaskList() {
        let html = MarkdownParser.toHTML("- [x] Done\n- [ ] Todo")
        XCTAssertTrue(html.contains("checked"))
        XCTAssertTrue(html.contains("checkbox"))
    }

    func testParserRendersStrikethrough() {
        let html = MarkdownParser.toHTML("~~deleted~~")
        XCTAssertTrue(html.contains("<del>"))
    }

    func testParserStripsHTMLWhenSafe() {
        let html = MarkdownParser.toHTML("<script>alert(1)</script>", unsafe: false)
        XCTAssertFalse(html.contains("<script>"))
    }

    func testParserAllowsHTMLWhenUnsafe() {
        let html = MarkdownParser.toHTML("<div>hello</div>", unsafe: true)
        XCTAssertTrue(html.contains("<div>hello</div>"))
    }

    func testTagFilterBlocksDangerousTags() {
        // GFM tagfilter replaces dangerous tags with escaped versions
        let html = MarkdownParser.toHTML("<script>alert(1)</script>", unsafe: true)
        XCTAssertFalse(html.contains("<script>"))
    }

    func testTagFilterAllowsSafeTags() {
        let html = MarkdownParser.toHTML("<details><summary>click</summary>hi</details>", unsafe: true)
        XCTAssertTrue(html.contains("<details>"))
    }

    // MARK: - Front matter

    func testStripsFrontMatter() {
        let md = "---\ntitle: Test\ndate: 2026-01-01\n---\n# Hello"
        let html = MarkdownParser.toHTML(md)
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("Hello"))
        XCTAssertFalse(html.contains("title: Test"))
    }

    func testPreserveContentWithoutFrontMatter() {
        let html = MarkdownParser.toHTML("# No front matter here")
        XCTAssertTrue(html.contains("No front matter here"))
    }

    // MARK: - Emoji shortcodes

    func testEmojiShortcodeReplacement() {
        let html = MarkdownParser.toHTML(":rocket: launch!")
        XCTAssertTrue(html.contains("🚀"))
        XCTAssertFalse(html.contains(":rocket:"))
    }

    func testMultipleEmojiShortcodes() {
        let html = MarkdownParser.toHTML(":heart: :star: :fire:")
        XCTAssertTrue(html.contains("❤️"))
        XCTAssertTrue(html.contains("⭐"))
        XCTAssertTrue(html.contains("🔥"))
    }

    func testUnknownEmojiShortcodeUnchanged() {
        let html = MarkdownParser.toHTML(":nonexistent_emoji:")
        XCTAssertTrue(html.contains(":nonexistent_emoji:"))
    }

    // MARK: - buildSelfContainedHTML

    func testSelfContainedHTMLContainsRenderedContent() {
        let bundle = Bundle(identifier: "com.local.MDViewer") ?? .main
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# Hello", bundle: bundle)
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("Hello"))
        XCTAssertTrue(html.contains("markdown-body"))
    }

    func testSelfContainedHTMLContainsHighlightJS() {
        let bundle = Bundle(identifier: "com.local.MDViewer") ?? .main
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "test", bundle: bundle)
        XCTAssertTrue(html.contains("hljs"))
    }

}
