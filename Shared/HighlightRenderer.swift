import Foundation

/// Pre-renders syntax highlighting via highlight.js in JavaScriptCore.
///
/// Finds `<pre><code class="language-xxx">...</code></pre>` blocks in HTML,
/// calls `hljs.highlight(code, {language: xxx})` for each, and replaces
/// with highlighted HTML. No browser-side JavaScript needed.
enum HighlightRenderer {
    static func highlight(in html: String, bundle: Bundle = .main) -> String {
        guard html.contains("<code") else { return html }
        guard let ctx = cache.context(bundle: bundle) else { return html }

        let matches = Array(html.matches(of: codeBlockRegex))
        guard !matches.isEmpty else { return html }

        var result = ""
        var lastEnd = html.startIndex
        for match in matches {
            result += html[lastEnd ..< match.range.lowerBound]

            let lang = String(match.output.1)
            if lang == "math" || lang == "mermaid" {
                result += html[match.range]
            } else {
                let escaped = String(match.output.2).htmlUnescaped.jsEscaped
                let langSafe = lang.jsEscaped
                let js = """
                (function(){
                    try {
                        if (hljs.getLanguage('\(langSafe)')) {
                            return hljs.highlight('\(escaped)', {language: '\(langSafe)'}).value;
                        } else {
                            return hljs.highlightAuto('\(escaped)').value;
                        }
                    } catch(e) { return ''; }
                })()
                """
                if let highlighted = ctx.evaluateScript(js)?.toString(), !highlighted.isEmpty {
                    result += "<pre><code class=\"hljs language-\(lang.htmlEscaped)\">\(highlighted)</code></pre>"
                } else {
                    result += html[match.range]
                }
            }
            lastEnd = match.range.upperBound
        }
        result += html[lastEnd...]

        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(
        resource: "highlight.min",
        setup: "var module = undefined; var exports = undefined;",
        globalName: "hljs"
    )

    private nonisolated(unsafe) static let codeBlockRegex =
        /<pre><code class="language-([^"]+)">([\s\S]*?)<\/code><\/pre>/
}
