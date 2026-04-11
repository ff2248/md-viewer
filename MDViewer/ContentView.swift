import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @Bindable var globalSettings: GlobalSettings
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var collapsedIDs: Set<String> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var fileURL: URL?
    @StateObject private var webProxy = WebViewProxy()
    @StateObject private var fileWatcher = FileWatcher()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if document.text.isEmpty {
                    ContentUnavailableView("No Document", systemImage: "doc.text", description: Text("Open a .md file"))
                } else {
                    tocList
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 260, max: 400)
        } detail: {
            if document.text.isEmpty {
                emptyState
            } else {
                MarkdownWebView(proxy: webProxy, markdown: document.text)
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
        .onChange(of: globalSettings.renderOptions) { old, new in
            webProxy.options = new
            if old.bodyFontSize != new.bodyFontSize || old.codeFontSize != new.codeFontSize {
                webProxy.applyFontSizes()
            }
            if old.hardBreaks != new.hardBreaks || old.showFrontMatter != new.showFrontMatter {
                webProxy.forceRerender(markdown: document.text)
            }
        }
        .onChange(of: document.text) {
            headings = []
            selectedHeadingID = nil
            collapsedIDs = []
        }
        .focusedSceneValue(\.webViewProxy, webProxy)
        .focusedSceneValue(\.documentURL, fileURL)
        .focusedSceneValue(\.documentText, document.text)
        .inspector(isPresented: $globalSettings.showSettings) {
            SettingsView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }

    // MARK: - File URL Resolution

    private func resolveFileURL() {
        // DocumentGroup provides the file URL via NSDocumentController
        guard let doc = NSDocumentController.shared.currentDocument,
              let url = doc.fileURL else { return }
        fileURL = url
        webProxy.fileURL = url
        // Watch for external edits and auto-reload.
        // DocumentGroup(viewing:) does not auto-revert on file changes, so we
        // re-implement the DispatchSource watcher from the pre-DocumentGroup era.
        fileWatcher.watch(url) { newText in
            document.text = newText
            // Tell NSDocument the change is intentional (not a dirty user edit),
            // otherwise it will try to autosave and show "could not be autosaved"
            // when it detects the underlying file has changed.
            NSDocumentController.shared.currentDocument?.updateChangeCount(.changeCleared)
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
                Text(heading.text)
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
}
