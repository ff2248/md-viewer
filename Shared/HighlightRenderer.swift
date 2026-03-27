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

        let nsHTML = html as NSString
        let matches = Self.codeBlockRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var result = html
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let langRange = Range(match.range(at: 1), in: result),
                  let codeRange = Range(match.range(at: 2), in: result) else { continue }

            let lang = String(result[langRange])
            let code = String(result[codeRange]).htmlUnescaped

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
                result.replaceSubrange(fullRange, with: replacement)
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

    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: "<pre><code class=\"language-([^\"]+)\">([\\s\\S]*?)</code></pre>",
        options: []
    )
}
