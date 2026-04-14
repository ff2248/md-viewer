import Foundation
@testable import MDViewer
import Testing

/// Helper to build RenderOptions with specific overrides from defaults.
private func options(hardBreaks: Bool = RenderOptions.defaults.hardBreaks,
                     showFrontMatter: Bool = RenderOptions.defaults.showFrontMatter) -> RenderOptions
{
    RenderOptions(hardBreaks: hardBreaks, showFrontMatter: showFrontMatter,
                  bodyFontSize: RenderOptions.defaults.bodyFontSize,
                  codeFontSize: RenderOptions.defaults.codeFontSize)
}

/// Bundle for tests that need bundled resources.
private let testBundle = Bundle(identifier: "io.github.ff2248.MDViewer") ?? .main

// MARK: - MarkdownRenderer

struct MarkdownRendererSuite {
    @Test func errorHTMLContainsMessage() {
        let html = MarkdownRenderer.errorHTML(message: "File not found")
        #expect(html.contains("File not found"))
    }

    @Test func errorHTMLEscapesHTML() {
        let html = MarkdownRenderer.errorHTML(message: "<script>alert('xss')</script>")
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script"))
    }

    @Test func readFileSuccess() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).md")
        try "# Test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        #expect(try MarkdownRenderer.readMarkdownFile(at: tempFile).get() == "# Test")
    }

    @Test func readFileFailure() {
        let result = MarkdownRenderer.readMarkdownFile(at: URL(fileURLWithPath: "/nonexistent.md"))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test func hasMermaidDetectsBlock() {
        #expect(MarkdownRenderer.hasMermaid("```mermaid\ngraph TD\n```"))
    }

    @Test func selfContainedHTMLContainsMathML() {
        let html = MarkdownRenderer.buildSelfContainedHTML(
            markdown: "$x^2$", bundle: testBundle
        )
        // Temml renders math as MathML (no custom fonts needed on macOS)
        #expect(html.contains("<math"))
    }

    @Test func hasMermaidReturnsFalseForNormal() {
        #expect(!MarkdownRenderer.hasMermaid("# Hello\nNo mermaid here"))
    }

    @Test func selfContainedHTMLContainsRenderedContent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# Hello", bundle: testBundle)
        #expect(html.contains("<h1>"))
        #expect(html.contains("Hello"))
        #expect(html.contains("markdown-body"))
    }

    @Test func selfContainedHTMLContainsCSS() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "test", bundle: testBundle)
        #expect(html.contains("<style>"))
    }

    @Test func selfContainedHTMLIncludesMermaidWhenPresent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "```mermaid\ngraph TD\n```", bundle: testBundle)
        #expect(html.contains("mermaid"))
    }

    @Test func selfContainedHTMLExcludesMermaidWhenAbsent() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "# No mermaid", bundle: testBundle)
        #expect(!html.contains("mermaid.initialize"))
    }

    @Test func selfContainedHTMLInlinesLocalImagesWhenBaseURLProvided() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exptest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1x1 red PNG
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="))
        try pngData.write(to: dir.appendingPathComponent("pic.png"))

        let md = "![](pic.png)"
        let source = dir.appendingPathComponent("doc.md")
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: md, bundle: testBundle, baseURL: source)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("src=\"pic.png\""))
    }

    @Test func selfContainedHTMLKeepsRelativeImagesWithoutBaseURL() {
        let html = MarkdownRenderer.buildSelfContainedHTML(markdown: "![](pic.png)", bundle: testBundle)
        // No baseURL → images stay as relative references (will fail when HTML is moved)
        #expect(!html.contains("data:image/png;base64"))
    }
}

// MARK: - MarkdownParser

struct MarkdownParserSuite {
    @Test func rendersHeading() {
        let html = MarkdownParser.toHTML("# Hello")
        #expect(html.contains("<h1>"))
        #expect(html.contains("Hello"))
    }

    @Test func rendersGFMTable() {
        let html = MarkdownParser.toHTML("| A | B |\n|---|---|\n| 1 | 2 |")
        #expect(html.contains("<table>"))
        #expect(html.contains("<td>"))
    }

    @Test func rendersTaskList() {
        let html = MarkdownParser.toHTML("- [x] Done\n- [ ] Todo")
        #expect(html.contains("checked"))
        #expect(html.contains("checkbox"))
    }

    // Note: strikethrough, footnotes, and autolinks require cmark-gfm extensions
    // which may not load in the test target. Tested manually.

    @Test func tagFilterBlocksDangerousTags() {
        #expect(!MarkdownParser.toHTML("<script>alert(1)</script>").contains("<script>"))
    }

    @Test func tagFilterAllowsSafeTags() {
        #expect(MarkdownParser.toHTML("<details><summary>click</summary>hi</details>").contains("<details>"))
    }

    @Test func rawHTMLIsRendered() {
        #expect(MarkdownParser.toHTML("<div>hello</div>").contains("<div>hello</div>"))
    }

    @Test func emptyStringReturnsEmpty() {
        #expect(MarkdownParser.toHTML("").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func mathCodeBlockProducesLanguageMathClass() {
        #expect(MarkdownParser.toHTML("```math\nE = mc^2\n```").contains("language-math"))
    }
}

// MARK: - Hard Breaks

struct HardBreaksSuite {
    @Test func enabled() {
        #expect(MarkdownParser.toHTML("line1\nline2", options: options(hardBreaks: true)).contains("<br"))
    }

    @Test func disabled() {
        #expect(!MarkdownParser.toHTML("line1\nline2", options: options(hardBreaks: false)).contains("<br"))
    }
}

// MARK: - Front Matter

struct FrontMatterSuite {
    @Test func strippedByDefault() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\n---\n# Hello")
        #expect(html.contains("<h1>"))
        #expect(!html.contains("title: Test"))
    }

    @Test func renderedAsTable() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\nauthor: Alice\n---\n# Hello",
                                         options: options(showFrontMatter: true))
        #expect(html.contains("<table>"))
        #expect(html.contains("title"))
        #expect(html.contains("Alice"))
    }

    @Test func hiddenWhenDisabled() {
        let html = MarkdownParser.toHTML("---\ntitle: Test\n---\n# Hello",
                                         options: options(showFrontMatter: false))
        #expect(!html.contains("<table>"))
        #expect(html.contains("<h1>"))
    }

    @Test func preservedWithoutFrontMatter() {
        #expect(MarkdownParser.toHTML("# No front matter").contains("No front matter"))
    }

    @Test func malformedPreserved() {
        #expect(MarkdownParser.toHTML("---\nno closing\n# Hello").contains("Hello"))
    }

    @Test func emptyValue() throws {
        var text = "---\nkey:\n---\nContent"
        let table = MarkdownParser.extractFrontMatter(&text)
        #expect(try #require(table).contains("key"))
    }

    @Test func onlyDelimiters() {
        var text = "---\n---\nContent"
        #expect(MarkdownParser.extractFrontMatter(&text) == nil)
        #expect(text.contains("Content"))
    }
}

// MARK: - Emoji

struct EmojiSuite {
    @Test func singleReplacement() {
        let html = MarkdownParser.toHTML(":rocket: launch!")
        #expect(html.contains("🚀"))
        #expect(!html.contains(":rocket:"))
    }

    @Test func multipleReplacements() {
        let html = MarkdownParser.toHTML(":heart: :star: :fire:")
        #expect(html.contains("❤️"))
        #expect(html.contains("⭐"))
        #expect(html.contains("🔥"))
    }

    @Test func unknownUnchanged() {
        #expect(MarkdownParser.toHTML(":nonexistent_emoji:").contains(":nonexistent_emoji:"))
    }

    @Test func replacedEvenInInlineCode() {
        // Known behavior: emoji replacement runs before cmark-gfm parsing
        #expect(MarkdownParser.toHTML("`code :rocket: here`").contains("🚀"))
    }
}

// MARK: - StringExtensions

struct StringExtensionsSuite {
    @Test(arguments: [
        ("a\\b", "a\\\\b"),
        ("it's", "it\\'s"),
        ("a\nb", "a\\nb"),
        ("a\rb", "a\\rb"),
        ("line1\nit's a\\path", "line1\\nit\\'s a\\\\path"),
        ("", ""),
        ("a\u{2028}b", "a\\u2028b"),
        ("a\u{2029}b", "a\\u2029b"),
    ])
    func jsEscaped(input: String, expected: String) {
        #expect(input.jsEscaped == expected)
    }

    @Test func htmlUnescaped() {
        #expect("&amp; &lt; &gt; &quot; &#39;".htmlUnescaped == "& < > \" '")
        #expect("".htmlUnescaped == "")
    }

    @Test func htmlEscaped() {
        #expect("& < > \"".htmlEscaped == "&amp; &lt; &gt; &quot;")
        #expect("".htmlEscaped == "")
    }
}

// MARK: - RenderOptions

struct RenderOptionsSuite {
    @Test func defaults() {
        let d = RenderOptions.defaults
        #expect(d.hardBreaks)
        #expect(d.showFrontMatter)
        #expect(d.bodyFontSize == 15)
        #expect(d.codeFontSize == 12)
    }

    @Test func equatable() {
        #expect(RenderOptions.defaults == options())
        #expect(RenderOptions.defaults != options(hardBreaks: false))
    }

    @Test func fontSizeRanges() {
        #expect(RenderOptions.bodyFontSizeRange == 12 ... 24)
        #expect(RenderOptions.codeFontSizeRange == 10 ... 20)
    }

    @Test func markdownExtensions() {
        #expect(RenderOptions.markdownExtensions.contains("md"))
        #expect(RenderOptions.markdownExtensions.contains("markdown"))
        #expect(!RenderOptions.markdownExtensions.contains("txt"))
    }

    @Test func fromDefaultsEmpty() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-empty-\(UUID())"))
        #expect(RenderOptions.fromDefaults(defaults) == RenderOptions.defaults)
    }

    @Test func fromDefaultsCustom() throws {
        let defaults = try #require(UserDefaults(suiteName: "test-custom-\(UUID())"))
        defaults.set(false, forKey: SettingsKey.hardBreaks)
        defaults.set(20.0, forKey: SettingsKey.bodyFontSize)
        let opts = RenderOptions.fromDefaults(defaults)
        #expect(!opts.hardBreaks)
        #expect(opts.bodyFontSize == 20)
    }
}

// MARK: - inlineLocalImages

struct InlineLocalImagesSuite {
    private static let baseURL = URL(fileURLWithPath: "/tmp/test.md")

    @Test func skipsHttpUrls() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"https://example.com/img.png\">", relativeTo: Self.baseURL)
        #expect(result.contains("https://example.com/img.png"))
        #expect(!result.contains("data:"))
    }

    @Test func skipsDataUrls() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"data:image/png;base64,abc\">", relativeTo: Self.baseURL)
        #expect(result.contains("data:image/png"))
    }

    @Test func preservesNonexistentFile() {
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"nonexistent.png\">", relativeTo: Self.baseURL)
        #expect(result.contains("nonexistent.png"))
        #expect(!result.contains("base64"))
    }

    @Test func inlinesLocalPNG() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imgtest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1x1 red PNG
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="))
        let imgPath = dir.appendingPathComponent("red.png")
        try pngData.write(to: imgPath)

        let source = dir.appendingPathComponent("test.md")
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"red.png\">", relativeTo: source)
        #expect(result.contains("data:image/png;base64,"))
        #expect(!result.contains("red.png"))
    }

    @Test func blocksPathTraversal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imgtest-\(UUID())")
        let subdir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create file outside docs/
        let secret = dir.appendingPathComponent("secret.txt")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)

        let source = subdir.appendingPathComponent("test.md")
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"../secret.txt\">", relativeTo: source)
        #expect(!result.contains("base64"))
        #expect(result.contains("../secret.txt"))
    }

    @Test func blocksSiblingDirectoryPrefix() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imgtest-\(UUID())")
        let docsDir = dir.appendingPathComponent("docs")
        let evilDir = dir.appendingPathComponent("docs-evil")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evilDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = evilDir.appendingPathComponent("payload.png")
        try "fake".write(to: payload, atomically: true, encoding: .utf8)

        let source = docsDir.appendingPathComponent("test.md")
        let result = MarkdownRenderer.inlineLocalImages(in: "<img src=\"../docs-evil/payload.png\">", relativeTo: source)
        #expect(!result.contains("base64"))
    }
}

// MARK: - HighlightRenderer

struct HighlightRendererSuite {
    @Test func highlightsCodeBlock() {
        let html = "<pre><code class=\"language-js\">var x = 1;</code></pre>"
        let result = HighlightRenderer.highlight(in: html, bundle: testBundle)
        #expect(result.contains("hljs"))
    }

    @Test func skipsLanguageMath() {
        let html = "<pre><code class=\"language-math\">E = mc^2</code></pre>"
        let result = HighlightRenderer.highlight(in: html, bundle: testBundle)
        #expect(result.contains("language-math"))
        #expect(!result.contains("hljs"))
    }

    @Test func skipsLanguageMermaid() {
        let html = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let result = HighlightRenderer.highlight(in: html, bundle: testBundle)
        #expect(result.contains("language-mermaid"))
        #expect(!result.contains("hljs"))
    }

    @Test func noCodeBlocksUnchanged() {
        let html = "<p>No code here</p>"
        #expect(HighlightRenderer.highlight(in: html, bundle: testBundle) == html)
    }

    @Test func multipleCodeBlocks() {
        let html = """
        <pre><code class="language-js">var a = 1;</code></pre>
        <pre><code class="language-swift">let b = 2</code></pre>
        """
        let result = HighlightRenderer.highlight(in: html, bundle: testBundle)
        #expect(result.components(separatedBy: "hljs").count >= 3) // "hljs" appears at least twice
    }
}

// MARK: - MathRenderer

struct MathRendererSuite {
    @Test func noDollarSignsUnchanged() {
        let html = "<p>No math here</p>"
        #expect(MathRenderer.renderMath(in: html, bundle: testBundle) == html)
    }

    @Test func rendersMathCodeBlock() {
        let html = "<pre><code class=\"language-math\">E = mc^2</code></pre>"
        let result = MathRenderer.renderMath(in: html, bundle: testBundle)
        #expect(!result.contains("language-math"))
        #expect(result.contains("<math"))
    }

    @Test func rendersDisplayMath() {
        let html = "<p>$$E = mc^2$$</p>"
        let result = MathRenderer.renderMath(in: html, bundle: testBundle)
        #expect(result.contains("<math"))
        #expect(!result.contains("$$"))
    }

    @Test func rendersInlineMath() {
        let html = "<p>$x^2$</p>"
        let result = MathRenderer.renderMath(in: html, bundle: testBundle)
        #expect(result.contains("<math"))
    }

    @Test func doesNotRenderMathInsideCode() {
        let html = "<code>$x$</code>"
        let result = MathRenderer.renderMath(in: html, bundle: testBundle)
        #expect(!result.contains("<math"))
        #expect(result.contains("$x$"))
    }
}

// MARK: - XSS Prevention

struct XSSPreventionSuite {
    @Test func stripsImgOnerror() {
        let html = MarkdownRenderer.stripEventHandlers(in: "<img src=x onerror=\"alert(1)\">")
        #expect(!html.contains("onerror"))
        #expect(html.contains("<img src=x"))
    }

    @Test func stripsSvgOnload() {
        let html = MarkdownRenderer.stripEventHandlers(in: "<svg onload=\"alert(1)\">")
        #expect(!html.contains("onload"))
    }

    @Test func stripsUnquotedEventHandler() {
        let html = MarkdownRenderer.stripEventHandlers(in: "<img src=x onerror=alert(1)>")
        #expect(!html.contains("onerror"))
    }

    @Test func stripsCaseVariantEventHandler() {
        let html = MarkdownRenderer.stripEventHandlers(in: "<img ONERROR=\"alert(1)\">")
        #expect(!html.contains("ONERROR"))
    }

    @Test func preservesNormalAttributes() {
        let html = MarkdownRenderer.stripEventHandlers(in: "<img src=\"photo.jpg\" alt=\"nice\">")
        #expect(html.contains("src=\"photo.jpg\""))
        #expect(html.contains("alt=\"nice\""))
    }
}

// MARK: - FileMenuPruner

import AppKit

@MainActor
struct FileMenuPrunerSuite {
    /// Build an NSMenu matching what macOS gives us for a DocumentGroup(viewing:) File menu.
    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        let titles = [
            "New", "Open…", "Open Recent",
            "", // separator
            "Close", "Close All",
            "Save", "Save As…", "Duplicate", "Rename…", "Move To…", "Revert To Saved", "Revert To",
            "", // separator
            "Share",
            "", // separator
            "Print…",
        ]
        for title in titles {
            if title.isEmpty {
                menu.addItem(.separator())
            } else {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }
        return menu
    }

    @Test func prunesUnwantedItems() {
        let menu = makeFileMenu()
        FileMenuPruner.prune(menu)

        let visibleTitles = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
        #expect(visibleTitles == ["Open…", "Open Recent", "Close", "Close All", "Print…"])
    }

    @Test func hidesNewSaveDuplicateRenameMoveRevertShare() {
        let menu = makeFileMenu()
        FileMenuPruner.prune(menu)

        for prefix in FileMenuPruner.unwantedTitlePrefixes {
            let matched = menu.items.filter { $0.title.hasPrefix(prefix) }
            #expect(!matched.isEmpty, "No items matched prefix '\(prefix)' — test data is stale")
            for item in matched {
                #expect(item.isHidden, "Item '\(item.title)' should be hidden")
                #expect(!item.isEnabled, "Item '\(item.title)' should be disabled")
                #expect(item.keyEquivalent.isEmpty, "Item '\(item.title)' should have no key equivalent")
            }
        }
    }

    @Test func preservesWantedItems() {
        let menu = makeFileMenu()
        FileMenuPruner.prune(menu)

        let wantedTitles = ["Open…", "Open Recent", "Close", "Close All", "Print…"]
        for title in wantedTitles {
            let item = menu.items.first { $0.title == title }
            #expect(item != nil, "Expected '\(title)' to exist")
            #expect(item?.isHidden == false, "'\(title)' should be visible")
        }
    }

    @Test func collapsesAdjacentSeparators() {
        let menu = makeFileMenu()
        FileMenuPruner.prune(menu)

        // After hiding New, Save..Revert, Share, leading and trailing sections should not
        // have visible runs of separators.
        let visible = menu.items.filter { !$0.isHidden }
        // No two consecutive visible separators
        for i in 0 ..< visible.count - 1 {
            #expect(!(visible[i].isSeparatorItem && visible[i + 1].isSeparatorItem),
                    "Found adjacent visible separators at index \(i)")
        }
        // No leading separator
        #expect(visible.first?.isSeparatorItem == false, "Should not lead with a separator")
        // No trailing separator
        #expect(visible.last?.isSeparatorItem == false, "Should not trail with a separator")
    }

    @Test func idempotent() {
        let menu = makeFileMenu()
        FileMenuPruner.prune(menu)
        let afterFirst = menu.items.map { "\($0.title):\($0.isHidden)" }
        FileMenuPruner.prune(menu)
        let afterSecond = menu.items.map { "\($0.title):\($0.isHidden)" }
        #expect(afterFirst == afterSecond, "Pruning should be idempotent")
    }

    @Test func delegateForwardsToSwiftUIDelegate() {
        // Verify NSObject.forwardingTarget works: unknown selectors are forwarded.
        class StubDelegate: NSObject, NSMenuDelegate {
            var closedCount = 0
            func menuDidClose(_: NSMenu) {
                closedCount += 1
            }
        }
        let stub = StubDelegate()
        let pruner = FileMenuPruner()
        pruner.previousDelegate = stub

        // menuDidClose is not implemented on FileMenuPruner — should forward to stub
        // via forwardingTarget(for:).
        let menu = NSMenu(title: "Test")
        (pruner as NSMenuDelegate).menuDidClose?(menu)
        #expect(stub.closedCount == 1, "Unknown selector should forward to previousDelegate")
    }

    /// Runs AppDelegate's launch hook so tests don't pollute global state via
    /// direct `NSMenu.installFileMenuDelegateProtection()` calls. The swizzle is
    /// process-global once installed, so all swizzle tests must route through
    /// AppDelegate to faithfully verify that AppDelegate wires it up correctly.
    private func runAppDelegateLaunch() {
        let appDelegate = AppDelegate()
        appDelegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
    }

    /// End-to-end test: AppDelegate installs the swizzle, then SwiftUI's clobber
    /// attempt should be intercepted. This catches the regression where
    /// `applicationWillFinishLaunching` doesn't call `installFileMenuDelegateProtection`.
    @Test func appDelegateInstallsSwizzle() {
        runAppDelegateLaunch()

        let fileMenu = NSMenu(title: "File")
        let pruner = FileMenuPruner()
        fileMenu.delegate = pruner

        class FakeSwiftUIDelegate: NSObject, NSMenuDelegate {}
        let swiftUIImposter = FakeSwiftUIDelegate()
        fileMenu.delegate = swiftUIImposter

        #expect(fileMenu.delegate === pruner,
                "AppDelegate.applicationWillFinishLaunching must install swizzle to protect File menu delegate")
        #expect(pruner.previousDelegate === swiftUIImposter,
                "Incoming delegate should be stored for forwarding")
    }

    /// Non-File menus should NOT be protected — only the File menu.
    @Test func swizzleOnlyProtectsFileMenu() {
        runAppDelegateLaunch()

        let editMenu = NSMenu(title: "Edit")
        let pruner = FileMenuPruner()
        editMenu.delegate = pruner

        class OtherDelegate: NSObject, NSMenuDelegate {}
        let other = OtherDelegate()
        editMenu.delegate = other

        // For non-File menus, delegate should be replaceable normally
        #expect(editMenu.delegate === other, "Non-File menus should not be protected by the swizzle")
    }
}
