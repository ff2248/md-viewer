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

    /// Renders Markdown to HTML via cmark-gfm, highlight.js, and Temml.
    static func renderToHTML(_ markdown: String, bundle: Bundle, options: RenderOptions = .defaults) -> String {
        var html = MarkdownParser.toHTML(markdown, options: options)
        html = HighlightRenderer.highlight(in: html, bundle: bundle)
        html = MathRenderer.renderMath(in: html, bundle: bundle)
        html = stripEventHandlers(in: html)
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

    /// Builds a self-contained HTML document (used for Quick Look and HTML export).
    ///
    /// Markdown is parsed by cmark-gfm, then syntax highlighting and math
    /// are pre-rendered via JavaScriptCore. Only CSS is inlined — no JS
    /// is needed at render time, except Mermaid which requires a DOM and
    /// is conditionally included when diagram blocks are present.
    ///
    /// Uses string concatenation (not interpolation) because JS files
    /// contain `\(` which would break Swift string interpolation.
    static func buildSelfContainedHTML(markdown: String, bundle: Bundle, baseURL: URL? = nil, options: RenderOptions = .defaults) -> String {
        var renderedHTML = renderToHTML(markdown, bundle: bundle, options: options)
        if let baseURL {
            renderedHTML = inlineLocalImages(in: renderedHTML, relativeTo: baseURL)
        }

        var html = "<!DOCTYPE html><html><head><meta charset='UTF-8'>"

        for name in cssFiles {
            let css = readBundleResource(name, "css", bundle: bundle)
            html += "<style>" + css + "</style>"
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
            let fileURL = dir.appendingPathComponent(src).standardizedFileURL
            // Prevent path traversal outside the document's directory
            guard fileURL.path.hasPrefix(dir.standardizedFileURL.path + "/"),
                  let data = try? Data(contentsOf: fileURL) else { return String(match.output.0) }
            let mime = switch fileURL.pathExtension.lowercased() {
            case "png": "image/png"
            case "jpg", "jpeg": "image/jpeg"
            case "gif": "image/gif"
            case "svg": "image/svg+xml"
            case "webp": "image/webp"
            default: "application/octet-stream"
            }
            let b64 = data.base64EncodedString()
            return "src=\"data:\(mime);base64,\(b64)\""
        }
    }

    /// Strip all on* event handler attributes to prevent XSS via raw HTML in Markdown.
    /// GFM tagfilter only blocks specific tags (script, style, etc.) but not event handlers
    /// on allowed tags like <img onerror="...">.
    static func stripEventHandlers(in html: String) -> String {
        html.replacing(eventHandlerRegex, with: "")
    }

    private nonisolated(unsafe) static let eventHandlerRegex = /\s+on\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/
        .ignoresCase()
    private nonisolated(unsafe) static let imgSrcRegex = /src="([^"]+)"/

    private static let cssFiles = ["github-markdown", "github.min", "github-dark.min", "temml.min", "custom"]
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
