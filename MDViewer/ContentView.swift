import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var collapsedIDs: Set<String> = []
    @StateObject private var webProxy = WebViewProxy()

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.columnVisibility) {
            Group {
                if appState.markdown.isEmpty {
                    ContentUnavailableView("No Document", systemImage: "doc.text", description: Text("Open a .md file or drag one here"))
                } else {
                    tocList
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 260, max: 400)
        } detail: {
            if appState.markdown.isEmpty {
                emptyState
            } else {
                MarkdownWebView(proxy: webProxy, markdown: appState.markdown)
            }
        }
        .onAppear {
            webProxy.onHeadingsLoaded = { headings = $0 }
            webProxy.onOpenRelativeFile = { appState.openFile($0) }
            webProxy.fileURL = appState.fileURL
            webProxy.options = appState.renderOptions
        }
        .onChange(of: appState.fileURL) {
            webProxy.fileURL = appState.fileURL
        }
        .onChange(of: appState.renderOptions) { old, new in
            webProxy.options = new
            if old.bodyFontSize != new.bodyFontSize || old.codeFontSize != new.codeFontSize {
                webProxy.applyFontSizes()
            }
            if old.hardBreaks != new.hardBreaks || old.showFrontMatter != new.showFrontMatter {
                webProxy.forceRerender(markdown: appState.markdown)
            }
        }
        .onChange(of: appState.markdown) {
            headings = []
            selectedHeadingID = nil
            collapsedIDs = []
        }
        .focusedSceneValue(\.webViewProxy, webProxy)
        .inspector(isPresented: $appState.showSettings) {
            SettingsView()
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
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

    /// Headings filtered by collapse state.
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

    /// Handle ← (collapse) and → (expand) on selected heading.
    private func handleArrowKey(collapse: Bool) -> KeyPress.Result {
        guard let id = selectedHeadingID,
              let heading = headings.first(where: { $0.id == id }) else { return .ignored }

        if collapse {
            // ← : collapse if expanded with children, otherwise select parent
            if hasChildren(heading), !collapsedIDs.contains(heading.id) {
                toggleCollapse(heading)
                return .handled
            }
            // Select parent heading (nearest heading with lower level)
            if let parentID = findParent(of: heading) {
                selectedHeadingID = parentID
                return .handled
            }
        } else {
            // → : expand if collapsed with children
            if hasChildren(heading), collapsedIDs.contains(heading.id) {
                toggleCollapse(heading)
                return .handled
            }
        }
        return .ignored
    }

    /// Find the nearest ancestor heading (lower level) above this heading.
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
        case 1: .headline
        case 2: .subheadline
        default: .body
        }
    }
}
