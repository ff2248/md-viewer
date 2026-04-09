import Foundation
@testable import MDViewer
import Testing

struct LinkRouterSuite {
    // MARK: - External URLs

    @Test func httpLink() throws {
        let action = LinkRouter.classify("http://example.com", relativeTo: nil)
        #expect(try action == .openExternal(#require(URL(string: "http://example.com"))))
    }

    @Test func httpsLink() throws {
        let action = LinkRouter.classify("https://github.com/repo", relativeTo: nil)
        #expect(try action == .openExternal(#require(URL(string: "https://github.com/repo"))))
    }

    @Test func externalLinkIgnoresFileURL() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let action = LinkRouter.classify("https://example.com", relativeTo: fileURL)
        #expect(try action == .openExternal(#require(URL(string: "https://example.com"))))
    }

    // MARK: - Relative Markdown Links

    @Test func relativeMarkdownLink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linktest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("README.md")
        try "# Hello".write(to: target, atomically: true, encoding: .utf8)

        let source = dir.appendingPathComponent("README.zh-TW.md")
        let action = LinkRouter.classify("README.md", relativeTo: source)
        #expect(action == .openMarkdownFile(target))
    }

    @Test func relativeMarkdownLinkWithSubpath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linktest-\(UUID())")
        let subdir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = subdir.appendingPathComponent("guide.md")
        try "# Guide".write(to: target, atomically: true, encoding: .utf8)

        let source = dir.appendingPathComponent("README.md")
        let action = LinkRouter.classify("docs/guide.md", relativeTo: source)
        #expect(action == .openMarkdownFile(target))
    }

    @Test func nonexistentMarkdownLinkIgnored() {
        let source = URL(fileURLWithPath: "/tmp/test.md")
        let action = LinkRouter.classify("nonexistent.md", relativeTo: source)
        // File doesn't exist + no safe scheme → ignored
        #expect(action == .ignored)
    }

    @Test func markdownExtensionsRecognized() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linktest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("index.md")

        for ext in ["md", "markdown", "mdown", "mkd"] {
            let target = dir.appendingPathComponent("file.\(ext)")
            try "test".write(to: target, atomically: true, encoding: .utf8)
            let action = LinkRouter.classify("file.\(ext)", relativeTo: source)
            #expect(action == .openMarkdownFile(target), "Failed for extension: \(ext)")
        }
    }

    // MARK: - Non-markdown relative links

    @Test func nonMarkdownRelativeLinkIgnored() {
        let source = URL(fileURLWithPath: "/tmp/test.md")
        let action = LinkRouter.classify("style.css", relativeTo: source)
        // Relative path without safe scheme → ignored
        #expect(action == .ignored)
    }

    // MARK: - No file context

    @Test func relativeMarkdownLinkWithoutFileURL() {
        let action = LinkRouter.classify("README.md", relativeTo: nil)
        // No fileURL → can't resolve, no safe scheme → ignored
        #expect(action == .ignored)
    }

    // MARK: - Edge cases

    @Test func emptyHref() {
        let action = LinkRouter.classify("", relativeTo: nil)
        #expect(action == .ignored)
    }

    @Test func spacesInHrefIgnored() {
        // No safe scheme → ignored regardless of URL validity
        let action = LinkRouter.classify("some file.md", relativeTo: nil)
        #expect(action == .ignored)
    }

    @Test func mailtoLinkAllowed() throws {
        let action = LinkRouter.classify("mailto:user@example.com", relativeTo: nil)
        #expect(try action == .openExternal(#require(URL(string: "mailto:user@example.com"))))
    }

    @Test func javascriptSchemeBlocked() {
        let action = LinkRouter.classify("javascript:alert(1)", relativeTo: nil)
        #expect(action == .ignored)
    }

    @Test func fileSchemeBlocked() {
        let action = LinkRouter.classify("file:///etc/passwd", relativeTo: nil)
        #expect(action == .ignored)
    }
}
