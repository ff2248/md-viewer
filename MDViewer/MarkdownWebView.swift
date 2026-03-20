import SwiftUI
import WebKit

/// A heading extracted from rendered Markdown, used for TOC sidebar navigation.
struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

/// Proxy object for direct WKWebView access from outside MarkdownWebView.
/// Allows sidebar to scroll without going through SwiftUI's update cycle.
class WebViewProxy: ObservableObject {
    fileprivate(set) var webView: WKWebView?

    func scrollToHeading(_ id: String) {
        webView?.evaluateJavaScript("scrollToHeading('\(id)');") { _, _ in }
    }
}

/// Wraps WKWebView to render Markdown via the bundled template.html and JS libraries.
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let bundle: Bundle
    let proxy: WebViewProxy
    let onHeadingsLoaded: ([Heading]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeadingsLoaded: onHeadingsLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Private API: required for WKWebView to load bundled JS/CSS via file:// URLs
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "headings")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Private API: transparent background until content loads
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
        if context.coordinator.isTemplateReady {
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
        var isTemplateReady = false
        let onHeadingsLoaded: ([Heading]) -> Void

        init(onHeadingsLoaded: @escaping ([Heading]) -> Void) {
            self.onHeadingsLoaded = onHeadingsLoaded
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isTemplateReady = true
            if let markdown = pendingMarkdown {
                injectMarkdown(markdown, into: webView)
            }
        }

        func injectMarkdown(_ markdown: String, into webView: WKWebView) {
            let base64 = Data(markdown.utf8).base64EncodedString()
            webView.evaluateJavaScript("renderMarkdown('\(base64)');") { _, _ in }
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
