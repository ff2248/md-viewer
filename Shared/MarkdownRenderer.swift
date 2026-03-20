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

    /// Builds a self-contained HTML page with all JS/CSS inlined.
    ///
    /// Used by the Quick Look extension where external file loading is unavailable.
    /// Mermaid is excluded to keep the payload small (~800 KB vs ~3.5 MB).
    ///
    /// Note: Uses string concatenation (not interpolation) because JS files
    /// contain `\(` which would break Swift string interpolation.
    static func buildSelfContainedHTML(markdown: String, bundle: Bundle) -> String {
        let base64 = Data(markdown.utf8).base64EncodedString()

        var html = "<!DOCTYPE html><html><head><meta charset='UTF-8'>"

        // Inline CSS
        for name in cssFiles {
            html += "<style>" + readBundleResource(name, "css", bundle: bundle) + "</style>"
        }
        html += "<style>"
        html += "body{box-sizing:border-box;min-width:200px;max-width:980px;margin:0 auto;padding:45px;background:#fff;}"
        html += ".markdown-body{font-size:16px;}"
        html += ".task-list-item{list-style-type:none;}"
        html += ".task-list-item input[type=checkbox]{margin:0 .2em .25em -1.6em;}"
        html += "</style></head><body>"
        html += "<article class='markdown-body' id='content'></article>"

        // Inline JS (mermaid excluded — too large for Quick Look)
        for name in jsFilesWithoutMermaid {
            html += "<script>" + readBundleResource(name, "js", bundle: bundle) + "</script>"
        }

        // Rendering script: decode Base64 → UTF-8 → markdown-it → HTML
        html += "<script>"
        html += "try{"
        html += "var bin=atob('" + base64 + "');"
        html += "var bytes=new Uint8Array(bin.length);"
        html += "for(var i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);"
        html += "var text=new TextDecoder('utf-8').decode(bytes);"
        html += "var md=markdownit({html:true,linkify:true,highlight:function(str,lang){"
        html += "if(lang&&hljs.getLanguage(lang)){try{return hljs.highlight(str,{language:lang}).value}catch(e){}}"
        html += "return ''}});"
        html += "md.use(markdownitEmoji);"
        html += "md.use(markdownitTaskLists,{enabled:true,label:true});"
        html += "md.use(markdownitFrontMatter,function(){});"
        html += "md.use(texmath,{engine:katex,delimiters:'dollars'});"
        html += "document.getElementById('content').innerHTML=md.render(text);"
        html += "}catch(e){document.getElementById('content').innerHTML='<pre>'+e.message+'</pre>';}"
        html += "</script></body></html>"

        return html
    }

    // MARK: - Private

    private static let cssFiles = ["github-markdown", "github.min", "katex.min"]

    private static let jsFilesWithoutMermaid = [
        "markdown-it.min", "markdown-it-emoji.min", "markdown-it-task-lists.min",
        "markdown-it-front-matter.min", "katex.min", "markdown-it-texmath.min",
        "highlight.min",
        "hljs-typescript.min", "hljs-swift.min", "hljs-kotlin.min",
        "hljs-rust.min", "hljs-go.min", "hljs-ruby.min",
        "hljs-yaml.min", "hljs-dockerfile.min", "hljs-diff.min"
    ]

    private static func readBundleResource(_ name: String, _ ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }
}
