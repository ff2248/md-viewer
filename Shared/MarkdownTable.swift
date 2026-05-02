import Foundation

/// Slices a GFM markdown table down to a sub-table of selected rows
/// and columns. Used by "Copy as Markdown" so selecting two cells
/// across a 10-column table doesn't dump the entire table source.
enum MarkdownTable {
    /// Slice the table source markdown to a sub-table containing only
    /// the named body rows × columns, plus the header row for those
    /// columns. When `singleCell` is true and the selection resolves to
    /// exactly one cell, the cell's content is returned bare (without
    /// pipe wrappers or alignment row).
    ///
    /// `bodyRows` and `cols` are 0-based indices matching how cmark-gfm
    /// renders the table: `bodyRows[0]` is the first row in `<tbody>`;
    /// `cols[0]` is the leftmost column.
    ///
    /// Returns nil if the source doesn't parse as a table (header line
    /// + alignment line + at least one body line) or if any requested
    /// index is out of range.
    static func slice(source: String, bodyRows: [Int], cols: [Int], singleCell: Bool) -> String? {
        let nonEmpty = source.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard nonEmpty.count >= 2 else { return nil }

        let header = parseRow(nonEmpty[0])
        let alignment = parseRow(nonEmpty[1])
        let body = nonEmpty.dropFirst(2).map { parseRow($0) }
        guard !header.isEmpty, header.count == alignment.count else { return nil }

        if singleCell, bodyRows.count == 1, cols.count == 1 {
            let r = bodyRows[0], c = cols[0]
            guard body.indices.contains(r), body[r].indices.contains(c) else { return nil }
            return body[r][c]
        }

        guard cols.allSatisfy(header.indices.contains),
              bodyRows.allSatisfy(body.indices.contains)
        else { return nil }

        let pickedHeader = cols.map { header[$0] }
        let pickedAlignment = cols.map { alignment[$0] }
        let pickedBody = bodyRows.map { r in cols.map { c in c < body[r].count ? body[r][c] : "" } }

        var lines = ["| " + pickedHeader.joined(separator: " | ") + " |"]
        lines.append("| " + pickedAlignment.joined(separator: " | ") + " |")
        for row in pickedBody {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// Split a GFM table line by `|`, treating `\|` as a literal pipe
    /// inside a cell. Leading and trailing pipes (which GFM allows but
    /// doesn't require) are stripped before splitting; cell contents
    /// are whitespace-trimmed.
    static func parseRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        var cells: [String] = []
        var current = ""
        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            let c = trimmed[i]
            let next = trimmed.index(after: i)
            if c == "\\", next < trimmed.endIndex, trimmed[next] == "|" {
                current.append("\\|")
                i = trimmed.index(after: next)
                continue
            }
            if c == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                i = next
                continue
            }
            current.append(c)
            i = next
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
