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
/// Also pre-warms HighlightRenderer and MathRenderer JSContexts in background.
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
    private(set) var currentMarkdown: String = ""
    private let bundle: Bundle

    private static var cachedMermaidJS: String?
    static let sharedProcessPool = WKProcessPool()

    /// Marker in `template.html` replaced with inline `<style>` blocks
    /// for each entry in `cssFiles`. Keeping the substitution point as a
    /// single sentinel decouples the template's link layout from the CSS
    /// list — adding or reordering stylesheets is a one-line change here.
    static let cssInlineSentinel = "<!-- @inline-css -->"
    private static let cssFiles = ["github-markdown", "github.min", "github-dark.min", "temml.min", "custom"]

    /// Cached template HTML with the `cssInlineSentinel` replaced by inline
    /// `<style>` blocks. Built once per process. Returns `nil` only when
    /// the template resource itself cannot be read.
    private static var cachedInlinedTemplate: String?

    static func inlinedTemplate(bundle: Bundle) -> String? {
        if let cached = cachedInlinedTemplate { return cached }
        guard let templateURL = bundle.url(forResource: "template", withExtension: "html"),
              let templateHTML = try? String(contentsOf: templateURL, encoding: .utf8)
        else { return nil }
        var inlinedCSS = ""
        inlinedCSS.reserveCapacity(48000)
        for name in cssFiles {
            guard let url = bundle.url(forResource: name, withExtension: "css"),
                  let css = try? String(contentsOf: url, encoding: .utf8) else { continue }
            inlinedCSS += "<style>\n\(css)\n</style>\n"
        }
        let html = templateHTML.replacingOccurrences(of: cssInlineSentinel, with: inlinedCSS)
        cachedInlinedTemplate = html
        return html
    }

    init(bundle: Bundle = .main) {
        self.bundle = bundle

        let config = WKWebViewConfiguration()
        config.processPool = Self.sharedProcessPool
        config.websiteDataStore = .nonPersistent()
        let uc = WKUserContentController()
        config.userContentController = uc

        webView = NonClickThroughWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .clear

        super.init()

        (webView as? NonClickThroughWebView)?.copyAsMarkdownTarget = self

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

        // Start template load immediately. Inlining CSS into the HTML
        // string lets WebKit complete the navigation in one in-memory
        // pass instead of fetching five stylesheets via file:// URLs.
        if let html = Self.inlinedTemplate(bundle: bundle),
           let resourcesURL = bundle.resourceURL
        {
            webView.loadHTMLString(html, baseURL: resourcesURL)
        }

        // Pre-warm the highlight.js JSContext on a background thread so
        // the first render doesn't pay its cold-load cost on the main
        // thread.
        Task.detached(priority: .userInitiated) {
            _ = HighlightRenderer.highlight(in: "<pre><code class=\"language-js\">x</code></pre>", bundle: bundle)
        }
    }

    // MARK: - Find in Page

    struct FindResult {
        let total: Int
        let current: Int
    }

    func find(_ query: String) async -> FindResult {
        await evaluateFind("findInPage('\(query.jsEscaped)')")
    }

    func findNext() async -> FindResult {
        await evaluateFind("findNext()")
    }

    func findPrev() async -> FindResult {
        await evaluateFind("findPrev()")
    }

    func clearFind() {
        webView.evaluateJavaScript("clearFind()") { _, _ in }
    }

    private func evaluateFind(_ js: String) async -> FindResult {
        do {
            let result = try await webView.evaluateJavaScript(js)
            if let dict = result as? [String: Any],
               let total = dict["total"] as? Int,
               let current = dict["current"] as? Int
            {
                return FindResult(total: total, current: current)
            }
        } catch {}
        return FindResult(total: 0, current: 0)
    }

    func scrollToHeading(_ id: String) {
        webView.evaluateJavaScript("scrollToHeading('\(id.jsEscaped)');") { _, _ in }
    }

    func exportHTML(markdown: String, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = title.replacingOccurrences(of: ".md", with: ".html")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: markdown, bundle: bundle, baseURL: fileURL, options: options)
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

        withLightAppearance {
            let config = WKPDFConfiguration()
            self.webView.createPDF(configuration: config) { result in
                Task { @MainActor in self.restoreAppearance() }
                do {
                    try result.get().write(to: url)
                } catch {
                    Task { @MainActor in NSAlert(error: error).runModal() }
                }
            }
        }
    }

    func printContent() {
        withLightAppearance {
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false
            let op = self.webView.printOperation(with: printInfo)
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
            self.restoreAppearance()
        }
    }

    /// Copies the Markdown source of the current selection to the general
    /// pasteboard as plain text. Block-level granularity by default;
    /// `getSelectedBlockRange` narrows to per-cell indices when the
    /// selection sits in a single table, or per-`<li>` ranges when it
    /// sits in a single list, so a partial table or list selection
    /// emits just the touched cells / items instead of the whole block.
    func copySelectionAsMarkdown() {
        guard !currentMarkdown.isEmpty else { return }
        let snapshot = currentMarkdown
        let snapshotOptions = options
        webView.evaluateJavaScript("getSelectedBlockRange()") { result, _ in
            guard let dict = result as? [String: Any],
                  let start = dict["startLine"] as? Int,
                  let end = dict["endLine"] as? Int else { return }
            let preprocessed = MarkdownParser.preprocess(snapshot, options: snapshotOptions)
            guard let slice = MarkdownParser.extractLines(preprocessed, startLine: start, endLine: end) else { return }

            let output: String
            if let table = dict["table"] as? [String: Any],
               let bodyRows = table["bodyRows"] as? [Int],
               let cols = table["cols"] as? [Int],
               let singleCell = table["singleCell"] as? Bool,
               let sub = MarkdownTable.slice(source: slice, bodyRows: bodyRows, cols: cols, singleCell: singleCell)
            {
                output = sub
            } else if let list = dict["list"] as? [String: Any],
                      let ranges = list["ranges"] as? [[String: Int]]
            {
                let pieces = ranges.compactMap { r -> String? in
                    guard let s = r["startLine"], let e = r["endLine"] else { return nil }
                    return MarkdownParser.extractLines(preprocessed, startLine: s, endLine: e)
                }
                output = pieces.isEmpty ? slice : pieces.joined(separator: "\n")
            } else {
                output = slice
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(output, forType: .string)
        }
    }

    // MARK: - Light Mode Export

    private var savedAppearance: NSAppearance?

    /// Temporarily force light appearance on the WebView, wait for CSS
    /// media queries to re-evaluate, then execute the export action.
    private func withLightAppearance(action: @escaping () -> Void) {
        savedAppearance = webView.appearance
        webView.appearance = NSAppearance(named: .aqua)
        // Allow one layout cycle for CSS media queries to re-evaluate
        DispatchQueue.main.async(execute: action)
    }

    private func restoreAppearance() {
        webView.appearance = savedAppearance
        savedAppearance = nil
    }

    func forceRerender(markdown: String) {
        lastRendered = nil
        render(markdown: markdown)
    }

    func render(markdown: String) {
        currentMarkdown = markdown
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
/// Also injects a "Copy as Markdown" item into the right-click context menu.
private final class NonClickThroughWebView: WKWebView {
    weak var copyAsMarkdownTarget: WebViewProxy?

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        false
    }

    @MainActor
    override func willOpenMenu(_ menu: NSMenu, with _: NSEvent) {
        guard copyAsMarkdownTarget != nil else { return }
        // Avoid duplicates if AppKit reopens the same menu
        if menu.items.contains(where: { $0.action == #selector(copyAsMarkdownAction) && $0.target === self }) {
            return
        }
        let item = NSMenuItem(title: "Copy as Markdown",
                              action: #selector(copyAsMarkdownAction),
                              keyEquivalent: "")
        item.target = self
        // WKMenuItemIdentifierCopy is a private WebKit identifier (not in
        // public headers). If Apple ever renames it our item just falls
        // through to `addItem` and appears at the bottom — still
        // functional, just less discoverable.
        if let copyIndex = menu.items.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierCopy" }) {
            menu.insertItem(item, at: copyIndex + 1)
        } else {
            menu.addItem(item)
        }
    }

    @MainActor @objc private func copyAsMarkdownAction() {
        copyAsMarkdownTarget?.copySelectionAsMarkdown()
    }
}
