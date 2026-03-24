import SwiftUI
import WebKit

/// A heading extracted from rendered Markdown, used for TOC sidebar navigation.
struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

/// Proxy object for direct WKWebView access from outside MarkdownWebView.
class WebViewProxy: ObservableObject {
    fileprivate(set) var webView: WKWebView?

    func scrollToHeading(_ id: String) {
        webView?.evaluateJavaScript("scrollToHeading('\(id)');") { _, _ in }
    }
}

/// Wraps WKWebView to display pre-rendered Markdown HTML.
///
/// Flow:
/// 1. Load template.html (CSS only, no JS libraries)
/// 2. didFinish → inject JS libs via evaluateJavaScript (WKWebView has module/exports that break UMD)
/// 3. Inject cmark-gfm rendered HTML → JS post-processes (highlight, KaTeX, mermaid)
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let bundle: Bundle
    let proxy: WebViewProxy
    let onHeadingsLoaded: ([Heading]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(bundle: bundle, onHeadingsLoaded: onHeadingsLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "headings")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        proxy.webView = webView
        context.coordinator.pendingMarkdown = markdown
        loadTemplate(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard markdown != context.coordinator.lastRendered else { return }
        context.coordinator.pendingMarkdown = markdown
        if context.coordinator.isReady {
            context.coordinator.injectMarkdown(markdown, into: webView)
        }
    }

    private func loadTemplate(into webView: WKWebView) {
        guard let templateURL = bundle.url(forResource: "template", withExtension: "html"),
              let resourcesURL = bundle.resourceURL else { return }
        webView.loadFileURL(templateURL, allowingReadAccessTo: resourcesURL)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastRendered: String?
        var pendingMarkdown: String?
        var isReady = false
        private var mermaidInjected = false
        let bundle: Bundle
        let onHeadingsLoaded: ([Heading]) -> Void

        /// JS libraries read once from bundle, with module/exports neutralization.
        private static var cachedJSLibraries: String?
        private var jsLibraries: String {
            if let cached = Self.cachedJSLibraries { return cached }
            var js = "var module=undefined,exports=undefined,define=undefined;\n"
            for name in ["highlight.min", "katex.min"] {
                if let url = bundle.url(forResource: name, withExtension: "js"),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    js += content + "\n"
                }
            }
            Self.cachedJSLibraries = js
            return js
        }

        /// Mermaid JS read once from bundle (2.5 MB — only loaded when needed).
        private static var cachedMermaidJS: String?
        private var mermaidJS: String? {
            if let cached = Self.cachedMermaidJS { return cached }
            guard let url = bundle.url(forResource: "mermaid.min", withExtension: "js"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            Self.cachedMermaidJS = content
            return content
        }

        init(bundle: Bundle, onHeadingsLoaded: @escaping ([Heading]) -> Void) {
            self.bundle = bundle
            self.onHeadingsLoaded = onHeadingsLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(jsLibraries) { [weak self] _, _ in
                guard let self else { return }
                self.isReady = true
                if let markdown = self.pendingMarkdown {
                    self.injectMarkdown(markdown, into: webView)
                }
            }
        }

        func injectMarkdown(_ markdown: String, into webView: WKWebView) {
            let html = MarkdownParser.toHTML(markdown, unsafe: true)
            let base64 = Data(html.utf8).base64EncodedString()

            let hasMermaid = markdown.contains("```mermaid")
            if hasMermaid && !mermaidInjected, let js = mermaidJS {
                webView.evaluateJavaScript(js) { [weak self] _, _ in
                    self?.mermaidInjected = true
                    webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
                }
            } else {
                webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
            }

            lastRendered = markdown
            pendingMarkdown = nil
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "headings",
                  let list = message.body as? [[String: Any]] else { return }

            let headings = list.compactMap { item -> Heading? in
                guard let id = item["id"] as? String,
                      let level = item["level"] as? Int,
                      let text = item["text"] as? String else { return nil }
                return Heading(id: id, level: level, text: text)
            }
            DispatchQueue.main.async {
                self.onHeadingsLoaded(headings)
            }
        }
    }
}
