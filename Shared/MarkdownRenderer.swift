import Foundation

enum MarkdownRenderer {

    // MARK: - File I/O

    /// Reads a Markdown file with lossy UTF-8 decoding.
    static func readMarkdownFile(at url: URL) -> Result<String, Error> {
        do {
            let data = try Data(contentsOf: url)
            return .success(String(decoding: data, as: UTF8.self))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - HTML Generation

    /// Returns a simple error page.
    static func errorHTML(message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!DOCTYPE html>
        <html>
        <body style="font-family: -apple-system; padding: 40px; color: #666;">
            <h2>Cannot Open File</h2>
            <p>\(escaped)</p>
        </body>
        </html>
        """
    }

    /// Builds a self-contained HTML page with pre-rendered Markdown and inlined JS/CSS.
    ///
    /// Used by the Quick Look extension where external file loading is unavailable.
    /// Markdown is parsed to HTML by cmark-gfm in Swift — no JS parsing needed.
    /// Only highlight.js is inlined for syntax highlighting post-processing.
    /// Mermaid is excluded to keep the payload small.
    ///
    /// Note: Uses string concatenation (not interpolation) because JS files
    /// contain `\(` which would break Swift string interpolation.
    static func buildSelfContainedHTML(markdown: String, bundle: Bundle) -> String {
        // Parse Markdown to HTML in Swift (cmark-gfm)
        var renderedHTML = MarkdownParser.toHTML(markdown, unsafe: true)

        // Pre-render in Swift via JavaScriptCore (no browser JS needed at all)
        renderedHTML = HighlightRenderer.highlight(in: renderedHTML, bundle: bundle)
        renderedHTML = KaTeXRenderer.renderMath(in: renderedHTML, bundle: bundle)

        var html = "<!DOCTYPE html><html><head><meta charset='UTF-8'>"

        // Inline CSS only — no JavaScript needed in Quick Look
        for name in cssFiles {
            html += "<style>" + readBundleResource(name, "css", bundle: bundle) + "</style>"
        }
        html += "<style>"
        html += "body{box-sizing:border-box;margin:0;padding:16px 40px 40px 40px;background:#fff;}"
        html += ".markdown-body{font-size:16px;}"
        html += ".task-list-item{list-style-type:none;}"
        html += ".task-list-item input[type=checkbox]{margin:0 .2em .25em -1.6em;}"
        html += "</style></head><body>"
        html += "<article class='markdown-body'>"
        html += renderedHTML
        html += "</article>"

        // Conditionally include Mermaid only when diagrams are present
        let hasMermaid = markdown.contains("```mermaid")
        if hasMermaid {
            html += "<script>" + readBundleResource("mermaid.min", "js", bundle: bundle) + "</script>"
            html += "<script>"
            html += "document.querySelectorAll('pre code.language-mermaid').forEach(function(cb){"
            html += "var pre=cb.parentElement;var div=document.createElement('div');"
            html += "div.className='mermaid';div.textContent=cb.textContent;"
            html += "pre.parentElement.replaceChild(div,pre);});"
            html += "mermaid.initialize({startOnLoad:false,theme:'default'});mermaid.run();"
            html += "</script>"
        }

        html += "</body></html>"

        return html
    }

    // MARK: - Private

    private static let cssFiles = ["github-markdown", "github.min", "katex.min"]

    // katex.min and katex-auto-render not needed for Quick Look
    // (math is pre-rendered via JavaScriptCore in KaTeXRenderer)

    private static func readBundleResource(_ name: String, _ ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }
}
