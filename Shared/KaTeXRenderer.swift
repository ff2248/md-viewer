import Foundation
@preconcurrency import JavaScriptCore

/// Pre-renders LaTeX math expressions to HTML using KaTeX via JavaScriptCore.
///
/// Finds `$...$` (inline) and `$$...$$` (display) delimiters in HTML,
/// calls `katex.renderToString()` for each, and replaces with rendered HTML.
/// No browser-side JavaScript needed — the output is pure HTML + CSS.
enum KaTeXRenderer {
    static func renderMath(in html: String, bundle: Bundle = .main) -> String {
        guard html.contains("$") || html.contains("language-math") else { return html }
        guard let ctx = cache.context(bundle: bundle) else { return html }

        var result = replaceMathCodeBlocks(in: html, context: ctx)
        result = replaceDisplay(in: result, codeRanges: buildCodeBlockRanges(in: result), context: ctx)
        result = replaceInline(in: result, codeRanges: buildCodeBlockRanges(in: result), context: ctx)
        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(
        resource: "katex.min",
        globalName: "katex"
    )

    private static func renderKaTeX(_ expr: String, displayMode: Bool, context: JSContext) -> String? {
        let js = "try{katex.renderToString('\(expr.jsEscaped)',{displayMode:\(displayMode),throwOnError:false})}catch(e){''}"
        guard let result = context.evaluateScript(js)?.toString(), !result.isEmpty else { return nil }
        return result
    }

    /// ```math code blocks (rendered by cmark-gfm as <pre><code class="language-math">)
    private nonisolated(unsafe) static let mathCodeBlockRegex =
        /<pre><code class="language-math">([\s\S]*?)<\/code><\/pre>/

    private static func replaceMathCodeBlocks(in html: String, context: JSContext) -> String {
        let matches = Array(html.matches(of: mathCodeBlockRegex))
        guard !matches.isEmpty else { return html }
        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            result += html[lastEnd ..< match.range.lowerBound]
            let expr = String(match.output.1).htmlUnescaped.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rendered = renderKaTeX(expr, displayMode: true, context: context) {
                result += rendered
            } else {
                result += html[match.range]
            }
            lastEnd = match.range.upperBound
        }
        result += html[lastEnd...]
        return result
    }

    /// $$...$$  (display math)
    private nonisolated(unsafe) static let displayMathRegex = /\$\$(.+?)\$\$/
        .dotMatchesNewlines()

    /// $...$  (inline math) — Swift Regex doesn't support lookbehind,
    /// so we use a simple pattern and filter out $$ matches manually.
    private nonisolated(unsafe) static let inlineMathRegex = /\$(.+?)\$/
        .dotMatchesNewlines()

    private static func replaceDisplay(in html: String, codeRanges: [Range<String.Index>], context: JSContext) -> String {
        let matches = Array(html.matches(of: displayMathRegex))
        guard !matches.isEmpty else { return html }
        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            result += html[lastEnd ..< match.range.lowerBound]
            if !isInsideCodeBlock(match.range.lowerBound, codeRanges: codeRanges),
               let rendered = renderKaTeX(String(match.output.1), displayMode: true, context: context)
            {
                result += rendered
            } else {
                result += html[match.range]
            }
            lastEnd = match.range.upperBound
        }
        result += html[lastEnd...]
        return result
    }

    private static func replaceInline(in html: String, codeRanges: [Range<String.Index>], context: JSContext) -> String {
        let matches = Array(html.matches(of: inlineMathRegex))
        guard !matches.isEmpty else { return html }
        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            let start = match.range.lowerBound
            let end = match.range.upperBound
            result += html[lastEnd ..< match.range.lowerBound]

            // Skip $$ delimiters and code blocks
            let isDoubleDollar = (start > html.startIndex && html[html.index(before: start)] == "$")
                || (end < html.endIndex && html[end] == "$")

            if isDoubleDollar || isInsideCodeBlock(start, codeRanges: codeRanges) {
                result += html[match.range]
            } else if let rendered = renderKaTeX(String(match.output.1), displayMode: false, context: context) {
                result += rendered
            } else {
                result += html[match.range]
            }
            lastEnd = match.range.upperBound
        }
        result += html[lastEnd...]
        return result
    }

    private static func buildCodeBlockRanges(in html: String) -> [Range<String.Index>] {
        html.matches(of: codeBlockRangeRegex).map(\.range)
    }

    private nonisolated(unsafe) static let codeBlockRangeRegex =
        /<(?:code|pre)[^>]*>[\s\S]*?<\/(?:code|pre)>/

    private static func isInsideCodeBlock(_ position: String.Index, codeRanges: [Range<String.Index>]) -> Bool {
        codeRanges.contains { $0.contains(position) }
    }
}
