@testable import MDViewer
import Testing

private let sample = """
| Plan | Monthly | Yearly |
|------|--------:|-------:|
| A    | $26.97  | ~$5,637 |
| B    | $9.42   | ~$2,020 |
| C    | $0.07   | $0      |
"""

struct MarkdownTableSliceSuite {
    @Test func singleCellReturnsBareContent() {
        let result = MarkdownTable.slice(source: sample, bodyRows: [1], cols: [1], singleCell: true)
        #expect(result == "$9.42")
    }

    @Test func singleRowMultipleColumnsReturnsHeaderPlusRow() {
        let result = MarkdownTable.slice(source: sample, bodyRows: [0], cols: [0, 2], singleCell: false)
        #expect(result == """
        | Plan | Yearly |
        | ------ | -------: |
        | A | ~$5,637 |
        """)
    }

    @Test func multipleRowsSingleColumnReturnsHeaderPlusColumn() {
        let result = MarkdownTable.slice(source: sample, bodyRows: [0, 2], cols: [0], singleCell: false)
        #expect(result == """
        | Plan |
        | ------ |
        | A |
        | C |
        """)
    }

    @Test func multipleRowsMultipleColumnsReturnsRectangleWithHeader() {
        let result = MarkdownTable.slice(source: sample, bodyRows: [0, 1], cols: [0, 1], singleCell: false)
        #expect(result == """
        | Plan | Monthly |
        | ------ | --------: |
        | A | $26.97 |
        | B | $9.42 |
        """)
    }

    @Test func preservesAlignmentMarkers() {
        // The original alignment row uses `:--`/`--:` for left/right.
        // Slicing column index 2 should preserve `-------:` (right-aligned).
        let result = MarkdownTable.slice(source: sample, bodyRows: [0], cols: [2], singleCell: false)
        #expect(result?.contains("-------:") == true)
    }

    @Test func outOfRangeColumnReturnsNil() {
        #expect(MarkdownTable.slice(source: sample, bodyRows: [0], cols: [99], singleCell: false) == nil)
    }

    @Test func outOfRangeRowReturnsNil() {
        #expect(MarkdownTable.slice(source: sample, bodyRows: [99], cols: [0], singleCell: false) == nil)
    }

    @Test func malformedSourceReturnsNil() {
        // Too few lines to be a table (no alignment row).
        #expect(MarkdownTable.slice(source: "| just one row |", bodyRows: [], cols: [0], singleCell: false) == nil)
    }

    @Test func handlesSingleColumnTable() {
        let source = """
        | Item |
        |------|
        | A    |
        | B    |
        """
        #expect(MarkdownTable.slice(source: source, bodyRows: [1], cols: [0], singleCell: true) == "B")
        #expect(MarkdownTable.slice(source: source, bodyRows: [0, 1], cols: [0], singleCell: false) == """
        | Item |
        | ------ |
        | A |
        | B |
        """)
    }

    @Test func preservesCJKContent() {
        // Cell trim/split is grapheme-cluster based, so CJK content
        // round-trips byte-for-byte through the slicer.
        let source = """
        | 名稱 | 數量 |
        |------|-----:|
        | 蘋果 | 三   |
        | 香蕉 | 二   |
        """
        #expect(MarkdownTable.slice(source: source, bodyRows: [0], cols: [1], singleCell: true) == "三")
    }

    @Test func preservesRawHTMLInCell() {
        // <br> and similar inline HTML are GFM-legal table cell content
        // and must round-trip as-is (parseRow doesn't tokenize HTML).
        let source = """
        | Note |
        |------|
        | line1<br>line2 |
        """
        #expect(MarkdownTable.slice(source: source, bodyRows: [0], cols: [0], singleCell: true) == "line1<br>line2")
    }
}

struct MarkdownTableParseRowSuite {
    @Test func splitsBasicRow() {
        #expect(MarkdownTable.parseRow("| a | b | c |") == ["a", "b", "c"])
    }

    @Test func handlesRowWithoutLeadingTrailingPipes() {
        #expect(MarkdownTable.parseRow("a | b | c") == ["a", "b", "c"])
    }

    @Test func preservesEscapedPipeInsideCell() {
        // \| inside a cell is GFM's escape for a literal pipe; must not
        // split mid-cell, and must round-trip through the output.
        #expect(MarkdownTable.parseRow("| a \\| b | c |") == ["a \\| b", "c"])
    }

    @Test func trimsWhitespaceAroundCells() {
        #expect(MarkdownTable.parseRow("|   x   |   y   |") == ["x", "y"])
    }

    @Test func emptyCellPreserved() {
        #expect(MarkdownTable.parseRow("| a |  | c |") == ["a", "", "c"])
    }
}
