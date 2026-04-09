import Foundation

/// Classifies a clicked link href and determines routing action.
enum LinkRouter {
    enum Action: Equatable {
        case openExternal(URL)
        case openMarkdownFile(URL)
        case ignored
    }

    private static let safeSchemes: Set<String> = ["http", "https", "mailto"]

    /// Classify a link href relative to the current file's location.
    static func classify(_ href: String, relativeTo fileURL: URL?) -> Action {
        // External URLs
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            if let url = URL(string: href) {
                return .openExternal(url)
            }
            return .ignored
        }

        // Relative .md links
        let ext = (href as NSString).pathExtension.lowercased()
        if let fileURL, RenderOptions.markdownExtensions.contains(ext) {
            let resolved = fileURL.deletingLastPathComponent().appendingPathComponent(href)
            if FileManager.default.fileExists(atPath: resolved.path) {
                return .openMarkdownFile(resolved)
            }
        }

        // Fallback — only allow safe schemes
        if let url = URL(string: href),
           let scheme = url.scheme?.lowercased(),
           Self.safeSchemes.contains(scheme)
        {
            return .openExternal(url)
        }

        return .ignored
    }
}
