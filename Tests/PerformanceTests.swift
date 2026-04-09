@testable import MDViewer
import XCTest

final class PerformanceTests: XCTestCase {
    /// Sample markdown with various features for realistic benchmarking
    private static let sampleMarkdown: String = {
        var md = "---\ntitle: Performance Test\n---\n\n"
        md += "# Performance Test Document\n\n"

        // Headings + paragraphs
        for i in 1 ... 10 {
            md += "## Section \(i)\n\n"
            md += "This is paragraph content with **bold**, *italic*, and `inline code`. "
            md += "Also includes :rocket: emoji and a [link](https://example.com).\n\n"
        }

        // Table
        md += "| Column A | Column B | Column C |\n|---|---|---|\n"
        for i in 1 ... 5 {
            md += "| Row \(i)A | Row \(i)B | Row \(i)C |\n"
        }
        md += "\n"

        // Code blocks
        md += "```python\ndef fibonacci(n):\n    a, b = 0, 1\n    for _ in range(n):\n        a, b = b, a + b\n    return a\n```\n\n"
        md += "```swift\nstruct Parser {\n    static func parse(_ input: String) -> AST {\n        return AST(tokens: tokenize(input))\n    }\n}\n```\n\n"

        // Math
        md += "Inline math: $E = mc^2$ and $\\sum_{i=1}^{n} x_i$\n\n"
        md += "$$\\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$\n\n"

        // Task list
        md += "- [x] Completed task\n- [ ] Pending task\n- [x] Another done\n\n"

        // Footnotes
        md += "This has a footnote[^1].\n\n[^1]: Footnote content here.\n"

        return md
    }()

    // MARK: - Parsing Performance

    func testMarkdownParsingPerformance() {
        measure {
            _ = MarkdownParser.toHTML(Self.sampleMarkdown)
        }
    }

    // MARK: - Highlight Performance

    func testHighlightRendererPerformance() {
        let html = MarkdownParser.toHTML(Self.sampleMarkdown)
        measure {
            _ = HighlightRenderer.highlight(in: html)
        }
    }

    // MARK: - KaTeX Performance

    func testKaTeXRendererPerformance() {
        let html = MarkdownParser.toHTML(Self.sampleMarkdown)
        measure {
            _ = KaTeXRenderer.renderMath(in: html)
        }
    }

    // MARK: - Full Pipeline Performance

    func testFullRenderPipelinePerformance() {
        measure {
            _ = MarkdownRenderer.renderToHTML(Self.sampleMarkdown, bundle: .main)
        }
    }

    // MARK: - String Extensions Performance

    func testHtmlEscapingPerformance() {
        let longString = String(repeating: "Hello <world> & \"friends\" 'here' ", count: 1000)
        measure {
            _ = longString.htmlEscaped
        }
    }

    func testEmojiReplacementPerformance() {
        var md = ""
        for _ in 1 ... 100 {
            md += "Text with :rocket: and :heart: and :star: emojis.\n"
        }
        measure {
            _ = MarkdownParser.replaceEmojiShortcodes(md)
        }
    }
}
