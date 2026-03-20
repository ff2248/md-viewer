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

    // MARK: - buildSelfContainedHTML

    func testSelfContainedHTMLContainsBase64() {
        let bundle = Bundle(identifier: "com.local.MDViewer") ?? .main
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# Hello", bundle: bundle)
        let expected = Data("# Hello".utf8).base64EncodedString()
        XCTAssertTrue(html.contains(expected))
    }

    func testSelfContainedHTMLContainsMarkdownBody() {
        let bundle = Bundle(identifier: "com.local.MDViewer") ?? .main
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "test", bundle: bundle)
        XCTAssertTrue(html.contains("markdown-body"))
        XCTAssertTrue(html.contains("markdownit"))
    }
}
