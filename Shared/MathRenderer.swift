import Foundation
@preconcurrency import JavaScriptCore

/// LaTeX → MathML rendering via Temml in JavaScriptCore. Renders two math
/// constructs as a post-HTML regex pass:
///
/// - ` ```math ` fenced code blocks — cmark-gfm emits these as
///   `<pre><code class="language-math">...</code></pre>`, which is
///   structurally easiest to match on the rendered HTML.
/// - `$$...$$` display math, which can span `SOFTBREAK` siblings within
///   a paragraph. The regex is safe here because `$$` rarely appears in
///   normal prose.
///
/// Inline `$...$` is rendered earlier by `MathExtractor` at the cmark AST
/// level. Both call sites share the JSContext via `renderLatex`.
enum MathRenderer {
    /// Render a single LaTeX expression to MathML. Used by `MathExtractor`
    /// (inline) and by the post-HTML passes here (display, ` ```math `).
    /// One JSContext per process — Temml's bundle is several hundred KB,
    /// so both call sites share `cache`.
    static func renderLatex(_ latex: String, displayMode: Bool, bundle: Bundle) -> String? {
        guard let ctx = cache.context(bundle: bundle) else { return nil }
        let js = "try{temml.renderToString('\(latex.jsEscaped)',{displayMode:\(displayMode),throwOnError:false})}catch(e){''}"
        guard let result = ctx.evaluateScript(js)?.toString(), !result.isEmpty else { return nil }
        return result
    }

    static func renderMath(in html: String, bundle: Bundle = .main) -> String {
        guard html.contains("$$") || html.contains("language-math") else { return html }
        var result = replaceMathCodeBlocks(in: html, bundle: bundle)
        result = replaceDisplay(in: result, codeRanges: buildCodeBlockRanges(in: result), bundle: bundle)
        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(resource: "temml.min", globalName: "temml")

    /// ```math code blocks (rendered by cmark-gfm as <pre><code class="language-math">).
    /// Captures `<pre>`'s attributes as group 1 so we can carry cmark's
    /// `data-sourcepos` onto the rendered wrapper and keep "Copy as
    /// Markdown" working for math blocks.
    private nonisolated(unsafe) static let mathCodeBlockRegex =
        /<pre([^>]*)><code class="language-math">([\s\S]*?)<\/code><\/pre>/

    private static func replaceMathCodeBlocks(in html: String, bundle: Bundle) -> String {
        let matches = Array(html.matches(of: mathCodeBlockRegex))
        guard !matches.isEmpty else { return html }
        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            result += html[lastEnd ..< match.range.lowerBound]
            let preAttrs = String(match.output.1)
            let expr = String(match.output.2).htmlUnescaped.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rendered = renderLatex(expr, displayMode: true, bundle: bundle) {
                result += "<div\(preAttrs)>\(rendered)</div>"
            } else {
                result += html[match.range]
            }
            lastEnd = match.range.upperBound
        }
        result += html[lastEnd...]
        return result
    }

    /// $$...$$  (display math). May span newlines.
    private nonisolated(unsafe) static let displayMathRegex = /\$\$(.+?)\$\$/
        .dotMatchesNewlines()

    private static func replaceDisplay(in html: String, codeRanges: [Range<String.Index>], bundle: Bundle) -> String {
        let matches = Array(html.matches(of: displayMathRegex))
        guard !matches.isEmpty else { return html }
        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            result += html[lastEnd ..< match.range.lowerBound]
            if !isInsideCodeBlock(match.range.lowerBound, codeRanges: codeRanges),
               let rendered = renderLatex(String(match.output.1), displayMode: true, bundle: bundle)
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

    private static func buildCodeBlockRanges(in html: String) -> [Range<String.Index>] {
        html.matches(of: codeBlockRangeRegex).map(\.range)
    }

    private nonisolated(unsafe) static let codeBlockRangeRegex =
        /<(?:code|pre)[^>]*>[\s\S]*?<\/(?:code|pre)>/

    private static func isInsideCodeBlock(_ position: String.Index, codeRanges: [Range<String.Index>]) -> Bool {
        codeRanges.contains { $0.contains(position) }
    }
}
