import Foundation
import os

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

    // MARK: - Rendering

    /// Renders Markdown to HTML via cmark-gfm, highlight.js, and KaTeX.
    static func renderToHTML(_ markdown: String, bundle: Bundle) -> String {
        var html = MarkdownParser.toHTML(markdown, unsafe: true)
        html = HighlightRenderer.highlight(in: html, bundle: bundle)
        html = KaTeXRenderer.renderMath(in: html, bundle: bundle)
        return html
    }

    /// Whether the Markdown contains Mermaid diagram blocks.
    static func hasMermaid(_ markdown: String) -> Bool {
        markdown.contains("```mermaid")
    }

    // MARK: - HTML Generation

    /// Returns a simple error page.
    static func errorHTML(message: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <body style="font-family: -apple-system; padding: 40px; color: #666;">
            <h2>Cannot Open File</h2>
            <p>\(message.htmlEscaped)</p>
        </body>
        </html>
        """
    }

    /// Builds a self-contained HTML page for Quick Look.
    ///
    /// Markdown is parsed by cmark-gfm, then syntax highlighting and math
    /// are pre-rendered via JavaScriptCore. Only CSS is inlined — no JS
    /// is needed at render time, except Mermaid which requires a DOM and
    /// is conditionally included when diagram blocks are present.
    ///
    /// Uses string concatenation (not interpolation) because JS files
    /// contain `\(` which would break Swift string interpolation.
    static func buildSelfContainedHTML(markdown: String, bundle: Bundle, baseURL: URL? = nil) -> String {
        var renderedHTML = renderToHTML(markdown, bundle: bundle)
        if let baseURL = baseURL {
            renderedHTML = inlineLocalImages(in: renderedHTML, relativeTo: baseURL)
        }

        var html = "<!DOCTYPE html><html><head><meta charset='UTF-8'>"

        for name in cssFiles {
            html += "<style>" + readBundleResource(name, "css", bundle: bundle) + "</style>"
        }
        html += "</head><body>"
        html += "<article class='markdown-body'>"
        html += renderedHTML
        html += "</article>"

        if hasMermaid(markdown) {
            html += "<script>" + readBundleResource("mermaid.min", "js", bundle: bundle) + "</script>"
            html += "<script>"
            html += "document.querySelectorAll('pre code.language-mermaid').forEach(function(cb){"
            html += "var pre=cb.parentElement;var div=document.createElement('div');"
            html += "div.className='mermaid';div.textContent=cb.textContent;"
            html += "pre.parentElement.replaceChild(div,pre);});"
            html += "var mt=window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'default';"
            html += "mermaid.initialize({startOnLoad:false,theme:mt});mermaid.run();"
            html += "</script>"
        }

        html += "</body></html>"
        return html
    }

    // MARK: - Private

    /// Replace local image src with base64 data URIs for self-contained HTML.
    static func inlineLocalImages(in html: String, relativeTo baseURL: URL) -> String {
        let dir = baseURL.deletingLastPathComponent()
        return html.replacing(imgSrcRegex) { match in
            let src = String(match.output.1)
            // Skip URLs and data URIs
            if src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("data:") {
                return String(match.output.0)
            }
            let fileURL = dir.appendingPathComponent(src)
            guard let data = try? Data(contentsOf: fileURL) else { return String(match.output.0) }
            let mime: String
            switch fileURL.pathExtension.lowercased() {
            case "png": mime = "image/png"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "svg": mime = "image/svg+xml"
            case "webp": mime = "image/webp"
            default: mime = "application/octet-stream"
            }
            let b64 = data.base64EncodedString()
            return "src=\"data:\(mime);base64,\(b64)\""
        }
    }

    nonisolated(unsafe) private static let imgSrcRegex = /src="([^"]+)"/

    private static let cssFiles = ["github-markdown", "github.min", "github-dark.min", "katex.min", "custom"]
    private static let resourceCache = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    private static func readBundleResource(_ name: String, _ ext: String, bundle: Bundle) -> String {
        let key = "\(name).\(ext)"
        return resourceCache.withLock { cache in
            if let cached = cache[key] { return cached }
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            cache[key] = content
            return content
        }
    }
}
