import SwiftUI
import WebKit

/// A heading extracted from rendered Markdown, used for TOC sidebar navigation.
struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

/// Manages a pre-loaded WKWebView with template + JS libraries already injected.
/// Created at app launch so the WebView is ready before the user opens a file.
class WebViewProxy: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    var onHeadingsLoaded: (([Heading]) -> Void)?

    private var isReady = false
    private var pendingMarkdown: String?
    private var lastRendered: String?
    private var mermaidInjected = false
    private let bundle: Bundle

    private static var cachedJSLibraries: String?
    private static var cachedMermaidJS: String?

    init(bundle: Bundle = .main) {
        self.bundle = bundle

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let uc = WKUserContentController()
        config.userContentController = uc

        self.webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        super.init()

        uc.add(self, name: "headings")
        webView.navigationDelegate = self

        // Start loading template + CSS immediately
        if let templateURL = bundle.url(forResource: "template", withExtension: "html"),
           let resourcesURL = bundle.resourceURL {
            webView.loadFileURL(templateURL, allowingReadAccessTo: resourcesURL)
        }
    }

    func scrollToHeading(_ id: String) {
        webView.evaluateJavaScript("scrollToHeading('\(id)');") { _, _ in }
    }

    /// Called when markdown content changes. If WebView is ready, renders immediately.
    func render(markdown: String) {
        guard markdown != lastRendered else { return }
        pendingMarkdown = markdown
        if isReady {
            injectMarkdown(markdown)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Template loaded — now inject JS libraries
        webView.evaluateJavaScript(jsLibraries) { [weak self] _, _ in
            guard let self else { return }
            self.isReady = true
            if let md = self.pendingMarkdown {
                self.injectMarkdown(md)
            }
        }
    }

    // MARK: - WKScriptMessageHandler

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
            self.onHeadingsLoaded?(headings)
        }
    }

    // MARK: - Private

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

    private var mermaidJS: String? {
        if let cached = Self.cachedMermaidJS { return cached }
        guard let url = bundle.url(forResource: "mermaid.min", withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        Self.cachedMermaidJS = content
        return content
    }

    private func injectMarkdown(_ markdown: String) {
        let html = MarkdownParser.toHTML(markdown, unsafe: true)
        let base64 = Data(html.utf8).base64EncodedString()

        let hasMermaid = markdown.contains("```mermaid")
        if hasMermaid && !mermaidInjected, let js = mermaidJS {
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                self?.mermaidInjected = true
                self?.webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
            }
        } else {
            webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
        }

        lastRendered = markdown
        pendingMarkdown = nil
    }
}

/// Thin NSViewRepresentable wrapper — the WebView is owned by WebViewProxy.
struct MarkdownWebView: NSViewRepresentable {
    let proxy: WebViewProxy
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        proxy.render(markdown: markdown)
        return proxy.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        proxy.render(markdown: markdown)
    }
}
