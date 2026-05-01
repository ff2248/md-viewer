import CMarkGFM
import Foundation

/// Closure that turns one LaTeX source span into MathML, or `nil` to fall
/// back to the original delimited text. The Bool is `true` for display math.
typealias MathRenderClosure = (_ latex: String, _ displayMode: Bool) -> String?

/// Walks a parsed cmark document and replaces inline `$...$` and single-line
/// display `$$...$$` math found inside text nodes with `HTML_INLINE` nodes
/// carrying pre-rendered MathML.
///
/// Operating at the AST text-node level gives this pass four structural
/// properties:
///
/// - Match scope is bounded by the text node, so a `$` in one table cell
///   cannot pair with a `$` in another cell.
/// - HTML attributes (URLs, alt text, titles) are stored as node properties,
///   not text children, and so are never visited.
/// - Code spans (`CMARK_NODE_CODE`) and code blocks (`CMARK_NODE_CODE_BLOCK`)
///   are different node types, so their content is naturally skipped.
/// - Text content is read raw (pre-HTML-escape), so math operators like
///   `<` and `>` reach the math renderer as their literal characters
///   instead of as `&lt;` / `&gt;` entities.
///
/// Multi-line display math (`$$\nx\n$$`) is delegated to `MathRenderer` —
/// cmark splits the body across `SOFTBREAK` nodes, which this pass does
/// not coalesce.
enum MathExtractor {
    /// Walk the document, mutating text nodes that contain math. `render`
    /// is called once per detected span; returning nil leaves the original
    /// delimited source in place.
    static func extract(in document: UnsafeMutablePointer<cmark_node>, render: MathRenderClosure) {
        // Collect node pointers first to avoid mutating the tree mid-iteration.
        for node in collectTextNodes(in: document) {
            processTextNode(node, render: render)
        }
    }

    // MARK: - Private

    private static func collectTextNodes(in document: UnsafeMutablePointer<cmark_node>) -> [UnsafeMutablePointer<cmark_node>] {
        // Leaf inline nodes (TEXT, CODE, HTML_INLINE, etc.) only emit ENTER —
        // never EXIT. Block nodes emit both. Filter on ENTER and node type.
        var nodes: [UnsafeMutablePointer<cmark_node>] = []
        guard let iter = cmark_iter_new(document) else { return nodes }
        defer { cmark_iter_free(iter) }
        while true {
            let event = cmark_iter_next(iter)
            if event == CMARK_EVENT_DONE { break }
            if event != CMARK_EVENT_ENTER { continue }
            guard let node = cmark_iter_get_node(iter) else { continue }
            if cmark_node_get_type(node) == CMARK_NODE_TEXT {
                nodes.append(node)
            }
        }
        return nodes
    }

    private static func processTextNode(_ node: UnsafeMutablePointer<cmark_node>, render: MathRenderClosure) {
        guard let cstr = cmark_node_get_literal(node) else { return }
        let literal = String(cString: cstr)
        guard literal.contains("$") else { return }

        let segments = split(literal: literal)
        guard !segments.isEmpty else { return }

        var anchor = node
        let first = segments[0]
        switch first {
        case let .text(content):
            cmark_node_set_literal(node, content)
        case let .math(latex, displayMode):
            anchor = replace(node, withMath: latex, displayMode: displayMode, render: render)
        }

        for segment in segments.dropFirst() {
            anchor = insertAfter(anchor, segment: segment, render: render)
        }
    }

    private static func replace(
        _ node: UnsafeMutablePointer<cmark_node>,
        withMath latex: String,
        displayMode: Bool,
        render: MathRenderClosure
    ) -> UnsafeMutablePointer<cmark_node> {
        if let mathML = render(latex, displayMode), let newNode = cmark_node_new(CMARK_NODE_HTML_INLINE) {
            cmark_node_set_literal(newNode, mathML)
            cmark_node_insert_before(node, newNode)
            cmark_node_unlink(node)
            cmark_node_free(node)
            return newNode
        }
        cmark_node_set_literal(node, fallbackText(latex, displayMode: displayMode))
        return node
    }

    private static func insertAfter(
        _ anchor: UnsafeMutablePointer<cmark_node>,
        segment: Segment,
        render: MathRenderClosure
    ) -> UnsafeMutablePointer<cmark_node> {
        switch segment {
        case let .text(content):
            guard let newNode = cmark_node_new(CMARK_NODE_TEXT) else { return anchor }
            cmark_node_set_literal(newNode, content)
            cmark_node_insert_after(anchor, newNode)
            return newNode
        case let .math(latex, displayMode):
            if let mathML = render(latex, displayMode), let newNode = cmark_node_new(CMARK_NODE_HTML_INLINE) {
                cmark_node_set_literal(newNode, mathML)
                cmark_node_insert_after(anchor, newNode)
                return newNode
            }
            guard let fallback = cmark_node_new(CMARK_NODE_TEXT) else { return anchor }
            cmark_node_set_literal(fallback, fallbackText(latex, displayMode: displayMode))
            cmark_node_insert_after(anchor, fallback)
            return fallback
        }
    }

    private static func fallbackText(_ latex: String, displayMode: Bool) -> String {
        displayMode ? "$$\(latex)$$" : "$\(latex)$"
    }

    // MARK: - Splitting (file-internal so unit tests in the same target can drive it directly)

    enum Segment: Equatable {
        case text(String)
        case math(String, displayMode: Bool)
    }

    /// Split a text node literal into alternating text and math segments
    /// using Pandoc `tex_math_dollars` rules:
    ///
    /// - inline `$...$`: open `$` not followed by whitespace or digit;
    ///   close `$` not preceded by whitespace and not followed by digit;
    ///   body contains no newline or `$`.
    /// - display `$$...$$`: same line, body is non-empty.
    ///
    /// Display math is matched first at each position so `$$x$$` does not
    /// fragment into two adjacent inline `$$x$$`. Returns an empty array
    /// when no math is found, so callers can short-circuit on `.isEmpty`.
    static func split(literal: String) -> [Segment] {
        var result: [Segment] = []
        var i = literal.startIndex
        var textStart = i
        while i < literal.endIndex {
            if literal[i] == "$" {
                if let m = matchDisplay(in: literal, openAt: i) {
                    flushText(literal[textStart ..< i], into: &result)
                    let bodyStart = literal.index(i, offsetBy: 2)
                    result.append(.math(String(literal[bodyStart ..< m.bodyEnd]), displayMode: true))
                    i = m.afterClose
                    textStart = i
                    continue
                }
                if let m = matchInline(in: literal, openAt: i) {
                    flushText(literal[textStart ..< i], into: &result)
                    let bodyStart = literal.index(after: i)
                    result.append(.math(String(literal[bodyStart ..< m.bodyEnd]), displayMode: false))
                    i = m.afterClose
                    textStart = i
                    continue
                }
            }
            i = literal.index(after: i)
        }
        if result.isEmpty { return [] }
        flushText(literal[textStart ..< literal.endIndex], into: &result)
        return result
    }

    private static func flushText(_ slice: Substring, into result: inout [Segment]) {
        if !slice.isEmpty {
            result.append(.text(String(slice)))
        }
    }

    private static func matchDisplay(in s: String, openAt: String.Index) -> (bodyEnd: String.Index, afterClose: String.Index)? {
        let next = s.index(after: openAt)
        guard next < s.endIndex, s[next] == "$" else { return nil }
        let bodyStart = s.index(after: next)
        var i = bodyStart
        while i < s.endIndex {
            let c = s[i]
            if c == "\n" { return nil }
            if c == "$" {
                let next2 = s.index(after: i)
                if next2 < s.endIndex, s[next2] == "$" {
                    if i == bodyStart { return nil }
                    return (bodyEnd: i, afterClose: s.index(after: next2))
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func matchInline(in s: String, openAt: String.Index) -> (bodyEnd: String.Index, afterClose: String.Index)? {
        let bodyStart = s.index(after: openAt)
        guard bodyStart < s.endIndex else { return nil }
        let firstChar = s[bodyStart]
        if firstChar.isWhitespace || firstChar.isNumber { return nil }
        if firstChar == "$" { return nil }

        var i = bodyStart
        while i < s.endIndex {
            let c = s[i]
            if c == "\n" { return nil }
            if c == "$" {
                let prev = s.index(before: i)
                if s[prev].isWhitespace { return nil }
                let after = s.index(after: i)
                if after < s.endIndex, s[after].isNumber { return nil }
                return (bodyEnd: i, afterClose: s.index(after: i))
            }
            i = s.index(after: i)
        }
        return nil
    }
}
