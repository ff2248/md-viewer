import Foundation
@testable import MDViewer
import Testing

private func options(showFrontMatter: Bool = RenderOptions.defaults.showFrontMatter) -> RenderOptions {
    RenderOptions(hardBreaks: RenderOptions.defaults.hardBreaks,
                  showFrontMatter: showFrontMatter,
                  bodyFontSize: RenderOptions.defaults.bodyFontSize,
                  codeFontSize: RenderOptions.defaults.codeFontSize)
}

struct MarkdownParserPreprocessSuite {
    @Test func preservesYAMLFrontMatter() {
        // preprocess preserves front matter so its line numbers match the
        // original source — required for "Copy as Markdown" to slice
        // selections that include the front-matter table.
        let input = """
        ---
        title: Hello
        ---
        # Body
        """
        #expect(MarkdownParser.preprocess(input, options: options()) == input)
    }

    @Test func replacesEmojiShortcodes() {
        let out = MarkdownParser.preprocess("hi :smile:", options: options())
        #expect(out == "hi 😄")
    }

    @Test func leavesPlainMarkdownUntouched() {
        let md = "# H1\n\nparagraph **bold**"
        let out = MarkdownParser.preprocess(md, options: options())
        #expect(out == md)
    }

    @Test func doesNotTreatMidDocumentDashesAsFrontMatter() {
        let md = "not front matter\n---\ntitle: X"
        let out = MarkdownParser.preprocess(md, options: options())
        #expect(out == md)
    }
}

struct MarkdownParserExtractLinesSuite {
    private let text = "line1\nline2\nline3\nline4"

    @Test func singleLine() {
        #expect(MarkdownParser.extractLines(text, startLine: 2, endLine: 2) == "line2")
    }

    @Test func multipleLines() {
        #expect(MarkdownParser.extractLines(text, startLine: 2, endLine: 3) == "line2\nline3")
    }

    @Test func fullDocument() {
        #expect(MarkdownParser.extractLines(text, startLine: 1, endLine: 4) == text)
    }

    @Test func outOfRangeReturnsNil() {
        #expect(MarkdownParser.extractLines(text, startLine: 1, endLine: 99) == nil)
    }

    @Test func invertedRangeReturnsNil() {
        #expect(MarkdownParser.extractLines(text, startLine: 3, endLine: 2) == nil)
    }

    @Test func zeroStartReturnsNil() {
        #expect(MarkdownParser.extractLines(text, startLine: 0, endLine: 2) == nil)
    }
}

struct MarkdownParserSourceposSuite {
    @Test func paragraphHasSourcepos() {
        let html = MarkdownParser.toHTML("hello world", options: options())
        #expect(html.contains("data-sourcepos=\"1:1-1:11\""))
    }

    @Test func headingAndParagraphHaveDistinctRanges() {
        let html = MarkdownParser.toHTML("# Title\n\nbody", options: options())
        #expect(html.contains("data-sourcepos=\"1:1-1:7\""))
        #expect(html.contains("data-sourcepos=\"3:1-3:4\""))
    }

    @Test func codeBlockHasSourcepos() {
        let md = "```swift\nlet x = 1\n```"
        let html = MarkdownParser.toHTML(md, options: options())
        #expect(html.contains("data-sourcepos=\"1:1-3:3\""))
    }

    @Test func listItemsHaveSourcepos() {
        let html = MarkdownParser.toHTML("- a\n- b", options: options())
        #expect(html.contains("data-sourcepos=\"1:1-1:3\""))
        #expect(html.contains("data-sourcepos=\"2:1-2:3\""))
    }
}

struct MarkdownParserFrontMatterSourceposSuite {
    /// With front matter, cmark sees body-only text (line 1 = first body
    /// line). Our rewrite must shift its line numbers back into the
    /// original file's line space so "Copy as Markdown" can slice from
    /// the same value it rendered from.
    @Test func bodyLineNumbersAreInOriginalSpace() {
        let md = """
        ---
        title: X
        ---

        # Body
        """
        let html = MarkdownParser.toHTML(md, options: options())
        #expect(html.contains("data-sourcepos=\"5:1-5:6\""))
    }

    @Test func bodyLineNumbersShiftAppliesWhenShowingFrontMatter() {
        let md = """
        ---
        title: X
        ---

        # Body
        """
        let html = MarkdownParser.toHTML(md, options: options(showFrontMatter: true))
        #expect(html.contains("data-sourcepos=\"5:1-5:6\""))
    }

    @Test func frontMatterTableTaggedWithItsOwnRange() {
        let md = """
        ---
        title: X
        ---

        # Body
        """
        let html = MarkdownParser.toHTML(md, options: options(showFrontMatter: true))
        // Closing "---" sits on line 3, so table covers 1:1-3:3.
        #expect(html.contains("<table data-sourcepos=\"1:1-3:3\">"))
    }

    @Test func bodyLineNumbersUnshiftedWithoutFrontMatter() {
        // Guard: no front matter → no offset applied (bare "hello" is line 1).
        let html = MarkdownParser.toHTML("hello", options: options())
        #expect(html.contains("data-sourcepos=\"1:1-1:5\""))
    }

    @Test func bodyLineNumbersShiftWithNoBlankLineAfterFrontMatter() {
        // No blank between closing "---" and body → body starts on line 4.
        let md = "---\ntitle: X\n---\n# Body"
        let html = MarkdownParser.toHTML(md, options: options())
        #expect(html.contains("data-sourcepos=\"4:1-4:6\""))
    }
}
