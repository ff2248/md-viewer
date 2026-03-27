import Foundation
@preconcurrency import JavaScriptCore

/// Pre-renders LaTeX math expressions to HTML using KaTeX via JavaScriptCore.
///
/// Finds `$...$` (inline) and `$$...$$` (display) delimiters in HTML,
/// calls `katex.renderToString()` for each, and replaces with rendered HTML.
/// No browser-side JavaScript needed — the output is pure HTML + CSS.
enum KaTeXRenderer {

    static func renderMath(in html: String, bundle: Bundle = .main) -> String {
        guard html.contains("$") else { return html }
        guard let ctx = cache.context(bundle: bundle) else { return html }

        var result = html
        result = replaceDisplay(in: result, context: ctx)
        result = replaceInline(in: result, context: ctx)
        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(
        resource: "katex.min",
        globalName: "katex"
    )

    // $$...$$  (display math)
    nonisolated(unsafe) private static let displayMathRegex = /\$\$(.+?)\$\$/
        .dotMatchesNewlines()

    // $...$  (inline math) — Swift Regex doesn't support lookbehind,
    // so we use a simple pattern and filter out $$ matches manually.
    nonisolated(unsafe) private static let inlineMathRegex = /\$(.+?)\$/
        .dotMatchesNewlines()

    private static func replaceDisplay(in html: String, context: JSContext) -> String {
        let matches = Array(html.matches(of: displayMathRegex))
        var result = html
        for match in matches.reversed() {
            let before = String(result[result.startIndex..<match.range.lowerBound])
            if isInsideCodeBlock(before) { continue }

            let expr = String(match.output.1)
            let js = "try{katex.renderToString('\(expr.jsEscaped)',{displayMode:true,throwOnError:false})}catch(e){''}"
            if let rendered = context.evaluateScript(js)?.toString(), !rendered.isEmpty {
                result.replaceSubrange(match.range, with: rendered)
            }
        }
        return result
    }

    private static func replaceInline(in html: String, context: JSContext) -> String {
        let matches = Array(html.matches(of: inlineMathRegex))
        var result = html
        for match in matches.reversed() {
            // Skip if this is part of a $$ delimiter
            let start = match.range.lowerBound
            let end = match.range.upperBound
            if start > result.startIndex && result[result.index(before: start)] == "$" { continue }
            if end < result.endIndex && result[end] == "$" { continue }

            let before = String(result[result.startIndex..<start])
            if isInsideCodeBlock(before) { continue }

            let expr = String(match.output.1)
            let js = "try{katex.renderToString('\(expr.jsEscaped)',{displayMode:false,throwOnError:false})}catch(e){''}"
            if let rendered = context.evaluateScript(js)?.toString(), !rendered.isEmpty {
                result.replaceSubrange(match.range, with: rendered)
            }
        }
        return result
    }

    private static func isInsideCodeBlock(_ textBefore: String) -> Bool {
        let codeOpens = textBefore.components(separatedBy: "<code").count - 1
        let codeCloses = textBefore.components(separatedBy: "</code>").count - 1
        if codeOpens > codeCloses { return true }
        let preOpens = textBefore.components(separatedBy: "<pre").count - 1
        let preCloses = textBefore.components(separatedBy: "</pre>").count - 1
        return preOpens > preCloses
    }
}
