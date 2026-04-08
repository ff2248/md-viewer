import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var collapsedIDs: Set<String> = []
    @StateObject private var webProxy = WebViewProxy()
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.columnVisibility) {
            if appState.markdown.isEmpty {
                ContentUnavailableView("No Document", systemImage: "doc.text", description: Text("Open a .md file or drag one here"))
            } else {
                tocList
                    .safeAreaInset(edge: .bottom, spacing: 0) { tocFooter }
            }
        } detail: {
            if appState.markdown.isEmpty {
                emptyState
            } else {
                MarkdownWebView(proxy: webProxy, markdown: appState.markdown)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        .onAppear {
                webProxy.onHeadingsLoaded = { self.headings = $0 }
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
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
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleCollapse(heading) }
                } else {
                    Spacer().frame(width: 20)
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
        .onChange(of: selectedHeadingID) { _, newValue in
            if let id = newValue {
                webProxy.scrollToHeading(id)
            }
        }
    }

    private var tocFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.indent")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(collapsedIDs.isEmpty ? .tertiary : .secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { expandAll() } }
                    .help("Expand All")

                Image(systemName: "list.bullet")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { collapseAll() } }
                    .help("Collapse All")

                Spacer()

                Image(systemName: "gearshape")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onTapGesture { openSettings() }
                    .help("Settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

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

    /// Whether a heading has any children (next heading is deeper level).
    private func hasChildren(_ heading: Heading) -> Bool {
        guard let idx = headings.firstIndex(where: { $0.id == heading.id }),
              idx + 1 < headings.count else { return false }
        return headings[idx + 1].level > heading.level
    }


    private func expandAll() {
        collapsedIDs.removeAll()
    }

    private func collapseAll() {
        collapsedIDs = Set(headings.filter { hasChildren($0) }.map(\.id))
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

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .subheadline
        default: .body
        }
    }
}
