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
        result = replaceMath(in: result, regex: Self.displayMathRegex, display: true, context: ctx)
        result = replaceMath(in: result, regex: Self.inlineMathRegex, display: false, context: ctx)
        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(
        resource: "katex.min",
        globalName: "katex"
    )

    private static let displayMathRegex = try! NSRegularExpression(
        pattern: "\\$\\$(.+?)\\$\\$", options: [.dotMatchesLineSeparators]
    )
    private static let inlineMathRegex = try! NSRegularExpression(
        pattern: "(?<!\\$)\\$(?!\\$)(.+?)(?<!\\$)\\$(?!\\$)", options: [.dotMatchesLineSeparators]
    )

    private static func replaceMath(in html: String, regex: NSRegularExpression, display: Bool, context: JSContext) -> String {
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let exprRange = Range(match.range(at: 1), in: result) else { continue }
            let expr = String(result[exprRange])

            let before = String(result[result.startIndex..<fullRange.lowerBound])
            if isInsideCodeBlock(before) { continue }

            let escaped = expr.jsEscaped
            let displayMode = display ? "true" : "false"
            let js = "try{katex.renderToString('\(escaped)',{displayMode:\(displayMode),throwOnError:false})}catch(e){''}"

            if let rendered = context.evaluateScript(js)?.toString(), !rendered.isEmpty {
                result.replaceSubrange(fullRange, with: rendered)
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
