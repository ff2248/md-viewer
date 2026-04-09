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
@MainActor
class WebViewProxy: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    var onHeadingsLoaded: (([Heading]) -> Void)?
    var onOpenRelativeFile: ((URL) -> Void)?

    private var isReady = false
    private var pendingMarkdown: String?
    private var lastRendered: String?
    private var mermaidInjected = false
    private let bundle: Bundle

    private static var cachedMermaidJS: String?
    private static let processPool = WKProcessPool()

    init(bundle: Bundle = .main) {
        self.bundle = bundle

        let config = WKWebViewConfiguration()
        config.processPool = Self.processPool
        config.websiteDataStore = .nonPersistent()
        let uc = WKUserContentController()
        config.userContentController = uc

        webView = NonClickThroughWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .clear

        super.init()

        let weakHandler = WeakScriptMessageHandler(self)
        uc.add(weakHandler, name: "headings")
        uc.add(weakHandler, name: "linkClicked")
        // Prevent web content from handling drops
        uc.addUserScript(WKUserScript(
            source: "document.addEventListener('dragover',function(e){e.preventDefault()},true);document.addEventListener('drop',function(e){e.preventDefault()},true);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        webView.navigationDelegate = self

        // 1. Start loading template + CSS immediately
        if let templateURL = bundle.url(forResource: "template", withExtension: "html"),
           let resourcesURL = bundle.resourceURL
        {
            webView.loadFileURL(templateURL, allowingReadAccessTo: resourcesURL)
        }

        // 2. Pre-warm JSContexts in background (so they're ready when user opens a file)
        Task.detached(priority: .userInitiated) {
            _ = HighlightRenderer.highlight(in: "<pre><code class=\"language-js\">x</code></pre>", bundle: bundle)
            _ = KaTeXRenderer.renderMath(in: "<p>$x$</p>", bundle: bundle)
        }
    }

    func scrollToHeading(_ id: String) {
        webView.evaluateJavaScript("scrollToHeading('\(id.jsEscaped)');") { _, _ in }
    }

    func exportHTML(markdown: String, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = title.replacingOccurrences(of: ".md", with: ".html")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: markdown, bundle: bundle, options: options)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func exportPDF(title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title.replacingOccurrences(of: ".md", with: ".pdf")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { result in
            do {
                try result.get().write(to: url)
            } catch {
                Task { @MainActor in NSAlert(error: error).runModal() }
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

    func forceRerender(markdown: String) {
        lastRendered = nil
        render(markdown: markdown)
    }

    func render(markdown: String) {
        guard markdown != lastRendered else { return }
        pendingMarkdown = markdown
        if isReady {
            injectMarkdown(markdown)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Links are handled by JS click handler → linkClicked message handler.
        // This delegate only handles initial page load and footnote anchor navigation.
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           url.fragment != nil, url.scheme == "file"
        {
            return .allow
        }
        return navigationAction.navigationType == .other ? .allow : .cancel
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        // Template loaded — WebView is ready
        isReady = true
        if let md = pendingMarkdown {
            injectMarkdown(md)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_: WKUserContentController,
                               didReceive message: WKScriptMessage)
    {
        if message.name == "linkClicked", let href = message.body as? String {
            handleLinkClick(href)
            return
        }

        guard message.name == "headings",
              let list = message.body as? [[String: Any]] else { return }

        let headings = list.compactMap { item -> Heading? in
            guard let id = item["id"] as? String,
                  let level = item["level"] as? Int,
                  let text = item["text"] as? String else { return nil }
            return Heading(id: id, level: level, text: text)
        }
        onHeadingsLoaded?(headings)
    }

    // MARK: - Private

    private var mermaidJS: String? {
        if let cached = Self.cachedMermaidJS { return cached }
        guard let url = bundle.url(forResource: "mermaid.min", withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        Self.cachedMermaidJS = content
        return content
    }

    private func handleLinkClick(_ href: String) {
        switch LinkRouter.classify(href, relativeTo: fileURL) {
        case let .openExternal(url):
            NSWorkspace.shared.open(url)
        case let .openMarkdownFile(url):
            onOpenRelativeFile?(url)
        case .ignored:
            break
        }
    }

    var fileURL: URL?
    var options: RenderOptions = .defaults

    func applyFontSizes() {
        let js = "document.documentElement.style.setProperty('--body-font-size','\(Int(options.bodyFontSize))px');" +
            "document.documentElement.style.setProperty('--code-font-size','\(Int(options.codeFontSize))px');"
        webView.evaluateJavaScript(js) { _, _ in }
    }

    private func injectMarkdown(_ markdown: String) {
        var html = MarkdownRenderer.renderToHTML(markdown, bundle: bundle, options: options)
        if let fileURL {
            html = MarkdownRenderer.inlineLocalImages(in: html, relativeTo: fileURL)
        }
        let base64 = Data(html.utf8).base64EncodedString()

        let hasMermaid = MarkdownRenderer.hasMermaid(markdown)
        if hasMermaid, !mermaidInjected, let js = mermaidJS {
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                self?.mermaidInjected = true
                self?.webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
            }
        } else {
            webView.evaluateJavaScript("renderHTML('\(base64)');") { _, _ in }
        }

        applyFontSizes()
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

    func makeNSView(context _: Context) -> WKWebView {
        proxy.webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        proxy.render(markdown: markdown)
    }
}

/// Breaks the retain cycle: WKUserContentController → WeakScriptMessageHandler -(weak)→ WebViewProxy.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

/// Prevents click-through on inactive windows.
/// WKWebView defaults acceptsFirstMouse to true, causing clicks that
/// activate the window to also trigger web content interactions.
private class NonClickThroughWebView: WKWebView {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        false
    }
}
