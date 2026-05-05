import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @Bindable var globalSettings: GlobalSettings
    /// Live text from FileWatcher. We never write back to `document.text` because
    /// mutating the FileDocument binding marks NSDocument dirty, which triggers
    /// "could not be autosaved" dialogs when the on-disk file has also changed.
    @State private var liveText: String?
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var collapsedIDs: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var fileURL: URL?
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findTotal = 0
    @State private var findCurrent = 0
    @FocusState private var findFieldFocused: Bool
    @StateObject private var webProxy: WebViewProxy
    @StateObject private var fileWatcher = FileWatcher()
    @Environment(HistoryStore.self) private var historyStore

    init(document: Binding<MarkdownDocument>, globalSettings: GlobalSettings) {
        _document = document
        self.globalSettings = globalSettings
        // The `wrappedValue:` autoclosure runs only when this view's
        // `@StateObject` storage is first installed — *not* on every
        // re-init that SwiftUI performs while resolving the view tree.
        // Building the proxy inline (vs. computing it as a `let` first)
        // is therefore load-bearing: without it, takeWarmProxy()/
        // WebViewProxy() would fire on every transient init and the
        // warm proxy could be consumed by a discarded StateObject.
        _webProxy = StateObject(wrappedValue: AppDelegate.takeWarmProxy() ?? WebViewProxy())
    }

    /// Text to display — live content from FileWatcher, or the original from the document.
    private var currentText: String {
        liveText ?? document.text
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if currentText.isEmpty {
                    ContentUnavailableView("No Document", systemImage: "doc.text", description: Text("Open a .md file"))
                } else {
                    tocList
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 260, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if showFindBar {
                    findBar
                }
                if currentText.isEmpty {
                    emptyState
                } else {
                    MarkdownWebView(proxy: webProxy, markdown: currentText)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    // Use NSWorkspace to go through Apple Event path — same as `open -a`,
                    // which macOS automatically handles as tabs when allowsAutomaticWindowTabbing is true.
                    NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL,
                                            configuration: NSWorkspace.OpenConfiguration())
                }
            }
            return true
        }
        .onAppear {
            webProxy.onHeadingsLoaded = { headings = $0 }
            webProxy.onOpenRelativeFile = { url in
                // For relative links, open in a new window via NSWorkspace
                NSWorkspace.shared.open(url)
            }
            webProxy.options = globalSettings.renderOptions
            resolveFileURL()
        }
        .task {
            // On first launch, onAppear may fire before the window becomes main,
            // so NSDocumentController.shared.currentDocument can be nil.
            // Retry with short delays until the URL is resolved.
            for _ in 0 ..< 20 {
                if fileURL != nil { return }
                try? await Task.sleep(for: .milliseconds(100))
                resolveFileURL()
            }
        }
        .onChange(of: globalSettings.renderOptions) { old, new in
            webProxy.options = new
            if old.bodyFontSize != new.bodyFontSize || old.codeFontSize != new.codeFontSize {
                webProxy.applyFontSizes()
            }
            if old.hardBreaks != new.hardBreaks || old.showFrontMatter != new.showFrontMatter {
                webProxy.forceRerender(markdown: currentText)
            }
        }
        .onChange(of: document.text) {
            // NSDocument silently reverted — fall back to the new document text.
            liveText = nil
            resetTableOfContents()
        }
        .onChange(of: liveText) {
            resetTableOfContents()
        }
        .focusedSceneValue(\.webViewProxy, webProxy)
        .focusedSceneValue(\.documentURL, fileURL)
        .focusedSceneValue(\.documentText, currentText)
        .focusedSceneValue(\.toggleFindBar, toggleFindBar)
        .inspector(isPresented: $globalSettings.showSettings) {
            SettingsView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }

    // MARK: - Find Bar

    private var findBar: some View {
        HStack(spacing: 6) {
            TextField("Find…", text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focused($findFieldFocused)
                .onSubmit { Task { await runFind(webProxy.findNext) } }
                .task(id: findQuery) {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await runFind { await webProxy.find(findQuery) }
                }

            if findTotal > 0 {
                Text("\(findCurrent) of \(findTotal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if !findQuery.isEmpty {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: { Task { await runFind(webProxy.findPrev) } }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(findTotal == 0)

            Button(action: { Task { await runFind(webProxy.findNext) } }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(findTotal == 0)

            Button(action: { closeFindBar() }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onKeyPress(.escape) {
            closeFindBar()
            return .handled
        }
    }

    func toggleFindBar() {
        if showFindBar {
            closeFindBar()
        } else {
            showFindBar = true
            findFieldFocused = true
        }
    }

    private func closeFindBar() {
        showFindBar = false
        findQuery = ""
        findTotal = 0
        findCurrent = 0
        webProxy.clearFind()
    }

    private func runFind(_ op: () async -> WebViewProxy.FindResult) async {
        let result = await op()
        findTotal = result.total
        findCurrent = result.current
    }

    // MARK: - File URL Resolution

    private func resetTableOfContents() {
        headings = []
        selectedHeadingID = nil
        collapsedIDs = []
    }

    private func resolveFileURL() {
        guard fileURL == nil else { return }
        guard let doc = NSDocumentController.shared.currentDocument,
              let url = doc.fileURL else { return }
        fileURL = url
        webProxy.fileURL = url
        historyStore.recordOpen(url)
        // Watch for external edits and auto-reload.
        // Update liveText (a local @State) instead of document.text so we never
        // dirty the FileDocument binding — prevents NSDocument autosave conflicts.
        // Also call forceRerender directly to ensure the WebView updates immediately.
        fileWatcher.watch(url) { newText in
            liveText = newText
            webProxy.forceRerender(markdown: newText)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Text("Drop a .md file here")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("or press ⌘O to open")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - TOC Sidebar

    private var tocList: some View {
        List(visibleHeadings, selection: $selectedHeadingID) { heading in
            HStack(spacing: 4) {
                if hasChildren(heading) {
                    Image(systemName: collapsedIDs.contains(heading.id) ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleCollapse(heading) }
                } else {
                    Spacer().frame(width: 16)
                }
                Text(attributedHeading(heading, selected: heading.id == selectedHeadingID))
                    .font(fontForLevel(heading.level))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(.leading, CGFloat((heading.level - 1) * 12))
            .tag(heading.id)
        }
        .onKeyPress(.leftArrow) { handleArrowKey(collapse: true) }
        .onKeyPress(.rightArrow) { handleArrowKey(collapse: false) }
        .onChange(of: selectedHeadingID) { _, newValue in
            if let id = newValue {
                webProxy.scrollToHeading(id)
            }
        }
    }

    // MARK: - Collapse Logic

    private var visibleHeadings: [Heading] {
        var result: [Heading] = []
        var skipBelow: Int?
        for heading in headings {
            if let threshold = skipBelow {
                if heading.level > threshold { continue }
                skipBelow = nil
            }
            result.append(heading)
            if collapsedIDs.contains(heading.id) {
                skipBelow = heading.level
            }
        }
        return result
    }

    private func hasChildren(_ heading: Heading) -> Bool {
        guard let idx = headings.firstIndex(where: { $0.id == heading.id }),
              idx + 1 < headings.count else { return false }
        return headings[idx + 1].level > heading.level
    }

    private func toggleCollapse(_ heading: Heading) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if collapsedIDs.contains(heading.id) {
                collapsedIDs.remove(heading.id)
            } else {
                collapsedIDs.insert(heading.id)
            }
        }
    }

    private func handleArrowKey(collapse: Bool) -> KeyPress.Result {
        guard let id = selectedHeadingID,
              let heading = headings.first(where: { $0.id == id }) else { return .ignored }

        if collapse {
            if hasChildren(heading), !collapsedIDs.contains(heading.id) {
                toggleCollapse(heading)
                return .handled
            }
            if let parentID = findParent(of: heading) {
                selectedHeadingID = parentID
                return .handled
            }
        } else {
            if hasChildren(heading), collapsedIDs.contains(heading.id) {
                toggleCollapse(heading)
                return .handled
            }
        }
        return .ignored
    }

    private func findParent(of heading: Heading) -> String? {
        guard let idx = headings.firstIndex(where: { $0.id == heading.id }) else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            if headings[i].level < heading.level {
                return headings[i].id
            }
        }
        return nil
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: .body.bold()
        default: .body
        }
    }

    /// Warm accent for inline `code` in TOC entries. Hand-picked per appearance
    /// because system `.brown` reads too dim against the light sidebar.
    private static let sidebarCodeColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.85, green: 0.62, blue: 0.42, alpha: 1.0)
            : NSColor(red: 0.85, green: 0.47, blue: 0.16, alpha: 1.0)
    })

    /// When the row is selected, the warm color is dropped so the system's
    /// selection inversion (white-on-accent) paints the whole row uniformly —
    /// an explicit `foregroundColor` would survive the inversion and tank
    /// contrast against the accent background.
    private func attributedHeading(_ heading: Heading, selected: Bool) -> AttributedString {
        if heading.segments.count == 1, !heading.segments[0].isCode {
            return AttributedString(heading.segments[0].text)
        }
        var result = AttributedString()
        for seg in heading.segments {
            var part = AttributedString(seg.text)
            if seg.isCode {
                part.font = .body.monospaced()
                if !selected {
                    part.foregroundColor = Self.sidebarCodeColor
                }
            }
            result.append(part)
        }
        return result
    }
}

struct ToggleFindBarKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var toggleFindBar: (() -> Void)? {
        get { self[ToggleFindBarKey.self] }
        set { self[ToggleFindBarKey.self] = newValue }
    }
}
