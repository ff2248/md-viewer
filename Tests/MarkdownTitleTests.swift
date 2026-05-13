@testable import MDViewer
import Testing

struct MarkdownTitleSuite {
    @Test func returnsFirstH1() {
        let md = "# Hello World\n\nBody"
        #expect(MarkdownTitle.extract(from: md) == "Hello World")
    }

    @Test func ignoresLeadingBlankLines() {
        let md = "\n\n\n# Title\n"
        #expect(MarkdownTitle.extract(from: md) == "Title")
    }

    @Test func skipsYAMLFrontmatter() {
        let md = """
        ---
        title: in frontmatter
        date: 2024-01-01
        ---
        # Real Title
        """
        #expect(MarkdownTitle.extract(from: md) == "Real Title")
    }

    @Test func ignoresH1InsideCodeFence() {
        let md = """
        ```
        # not a title
        ```
        # Actual Title
        """
        #expect(MarkdownTitle.extract(from: md) == "Actual Title")
    }

    @Test func ignoresH1InsideTildeCodeFence() {
        let md = "~~~\n# inside\n~~~\n# Real\n"
        #expect(MarkdownTitle.extract(from: md) == "Real")
    }

    @Test func doesNotMatchH2() {
        let md = "## Subtitle\n\nNo H1 here."
        #expect(MarkdownTitle.extract(from: md) == nil)
    }

    @Test func returnsNilForNoHeading() {
        #expect(MarkdownTitle.extract(from: "Just a paragraph.\n") == nil)
    }

    @Test func returnsNilForEmptyH1() {
        #expect(MarkdownTitle.extract(from: "# \n") == nil)
        #expect(MarkdownTitle.extract(from: "#   \n") == nil)
    }

    @Test func trimsTrailingWhitespace() {
        #expect(MarkdownTitle.extract(from: "#   Padded   \n") == "Padded")
    }

    @Test func truncatesOverlyLongTitles() {
        let title = String(repeating: "x", count: 500)
        let extracted = MarkdownTitle.extract(from: "# \(title)\n")
        #expect(extracted?.count == 200)
    }

    @Test func handlesLeadingTabsAndSpaces() {
        // Markdown allows up to 3 leading spaces before a heading; treat any
        // leading indentation tolerantly so casual files don't get skipped.
        #expect(MarkdownTitle.extract(from: "   # Indented\n") == "Indented")
    }
}
