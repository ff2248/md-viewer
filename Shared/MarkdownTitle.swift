import Foundation

/// Extract a human-readable title from raw markdown — the first H1, or
/// nil when none can be found in the leading portion of the document.
enum MarkdownTitle {
    /// How many lines to scan before giving up. Real titles live near the top.
    private static let lineLimit = 200
    /// Cap stored titles so a malformed `# ` heading can't bloat UserDefaults.
    private static let maxLength = 200

    static func extract(from markdown: String) -> String? {
        let lines = stripFrontmatter(markdown.split(separator: "\n", omittingEmptySubsequences: false))

        var inFence = false
        for line in lines.prefix(lineLimit) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return String(title.prefix(maxLength))
            }
        }
        return nil
    }

    /// Drop a YAML frontmatter block (`--- … ---`) if one opens the document.
    /// Returns `lines` unchanged when there is no frontmatter or when the
    /// opening `---` has no matching close.
    private static func stripFrontmatter(_ lines: [Substring]) -> [Substring] {
        guard let first = lines.first(where: { !$0.allSatisfy(\.isWhitespace) }),
              first.trimmingCharacters(in: .whitespaces) == "---"
        else { return lines }
        var sawOpen = false
        for (i, line) in lines.enumerated() {
            guard line.trimmingCharacters(in: .whitespaces) == "---" else { continue }
            if sawOpen { return Array(lines.dropFirst(i + 1)) }
            sawOpen = true
        }
        return lines
    }
}
