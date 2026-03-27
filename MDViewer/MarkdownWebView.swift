import SwiftUI
import WebKit

/// A heading extracted from rendered Markdown, used for TOC sidebar navigation.
struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

/// Manages a pre-loaded WKWebView and pre-warmed JSContexts for instant rendering.
///
/// At init: creates WKWebView + loads template (CSS only).
/// Also pre-warms HighlightRenderer and KaTeXRenderer JSContexts in background.
/// When user opens a file: Swift pre-renders everything → WKWebView just sets innerHTML.
class WebViewProxy: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    var onHeadingsLoaded: (([Heading]) -> Void)?

    private var isReady = false
    private var pendingMarkdown: String?
    private var lastRendered: String?
    private var mermaidInjected = false
    private let bundle: Bundle

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

        // 1. Start loading template + CSS immediately
        if let templateURL = bundle.url(forResource: "template", withExtension: "html"),
           let resourcesURL = bundle.resourceURL {
            webView.loadFileURL(templateURL, allowingReadAccessTo: resourcesURL)
        }

        // 2. Pre-warm JSContexts in background (so they're ready when user opens a file)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = HighlightRenderer.highlight(in: "<pre><code class=\"language-js\">x</code></pre>", bundle: bundle)
            _ = KaTeXRenderer.renderMath(in: "<p>$x$</p>", bundle: bundle)
        }
    }

    func scrollToHeading(_ id: String) {
        webView.evaluateJavaScript("scrollToHeading('\(id)');") { _, _ in }
    }

    func exportPDF(title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title.replacingOccurrences(of: ".md", with: ".pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { result in
            if case .success(let data) = result {
                try? data.write(to: url)
            }
        }
    }

    func printContent() {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    func render(markdown: String) {
        guard markdown != lastRendered else { return }
        pendingMarkdown = markdown
        if isReady {
            injectMarkdown(markdown)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Template loaded — WebView is ready (no JS libraries to inject anymore)
        isReady = true
        if let md = pendingMarkdown {
            injectMarkdown(md)
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

    private var mermaidJS: String? {
        if let cached = Self.cachedMermaidJS { return cached }
        guard let url = bundle.url(forResource: "mermaid.min", withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        Self.cachedMermaidJS = content
        return content
    }

    private func injectMarkdown(_ markdown: String) {
        // All rendering in Swift — WKWebView just displays the result
        var html = MarkdownParser.toHTML(markdown, unsafe: true)
        html = HighlightRenderer.highlight(in: html, bundle: bundle)
        html = KaTeXRenderer.renderMath(in: html, bundle: bundle)

        let base64 = Data(html.utf8).base64EncodedString()

        // Mermaid still needs browser JS (requires DOM)
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

struct WebViewProxyKey: FocusedValueKey {
    typealias Value = WebViewProxy
}

extension FocusedValues {
    var webViewProxy: WebViewProxy? {
        get { self[WebViewProxyKey.self] }
        set { self[WebViewProxyKey.self] = newValue }
    }
}

/// Thin NSViewRepresentable — the WebView is owned by WebViewProxy.
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
