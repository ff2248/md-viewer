import Cocoa
@preconcurrency import QuickLookUI

class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let bundle = Bundle(for: type(of: self))

        let html: String
        switch MarkdownRenderer.readMarkdownFile(at: fileURL) {
        case .success(let markdown):
            let defaults = UserDefaults.standard
            let hardBreaks = defaults.object(forKey: "hardBreaks") == nil || defaults.bool(forKey: "hardBreaks")
            let showFrontMatter = defaults.object(forKey: "showFrontMatter") == nil || defaults.bool(forKey: "showFrontMatter")
            html = MarkdownRenderer.buildSelfContainedHTML(markdown: markdown, bundle: bundle, baseURL: fileURL, hardBreaks: hardBreaks, showFrontMatter: showFrontMatter)
        case .failure(let error):
            html = MarkdownRenderer.errorHTML(message: error.localizedDescription)
        }

        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let previewSize = CGSize(width: 980, height: screenHeight * 0.8)

        return QLPreviewReply(
            dataOfContentType: .html,
            contentSize: previewSize
        ) { reply in
            reply.stringEncoding = .utf8
            reply.title = fileURL.lastPathComponent
            return Data(html.utf8)
        }
    }
}
