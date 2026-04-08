import Foundation
import RegexBuilder

/// Pre-renders syntax highlighting via highlight.js in JavaScriptCore.
///
/// Finds `<pre><code class="language-xxx">...</code></pre>` blocks in HTML,
/// calls `hljs.highlight(code, {language: xxx})` for each, and replaces
/// with highlighted HTML. No browser-side JavaScript needed.
enum HighlightRenderer {
    static func highlight(in html: String, bundle: Bundle = .main) -> String {
        guard html.contains("<code") else { return html }
        guard let ctx = cache.context(bundle: bundle) else { return html }

        var result = html
        // Replace in reverse order to preserve indices
        let matches = Array(result.matches(of: codeBlockRegex))
        for match in matches.reversed() {
            let lang = String(match.output.1)
            if lang == "math" || lang == "mermaid" { continue }
            let code = String(match.output.2).htmlUnescaped

            let js = """
            (function(){
                try {
                    if (hljs.getLanguage('\(lang)')) {
                        return hljs.highlight('\(code.jsEscaped)', {language: '\(lang)'}).value;
                    } else {
                        return hljs.highlightAuto('\(code.jsEscaped)').value;
                    }
                } catch(e) { return ''; }
            })()
            """

            if let highlighted = ctx.evaluateScript(js)?.toString(), !highlighted.isEmpty {
                let replacement = "<pre><code class=\"hljs language-\(lang)\">\(highlighted)</code></pre>"
                result.replaceSubrange(match.range, with: replacement)
            }
        }

        return result
    }

    // MARK: - Private

    private static let cache = JSContextCache(
        resource: "highlight.min",
        setup: "var module = undefined; var exports = undefined;",
        globalName: "hljs"
    )

    private nonisolated(unsafe) static let codeBlockRegex = Regex {
        "<pre><code class=\"language-"
        Capture { OneOrMore(.reluctant) { /[^"]/ } }
        "\">"
        Capture { ZeroOrMore(.reluctant) { /./ } }
        "</code></pre>"
    }
    .dotMatchesNewlines()
}
