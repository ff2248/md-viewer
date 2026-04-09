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
                        .safeAreaInset(edge: .bottom, spacing: 0) { tocFooter }
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
                footerButton("list.bullet.indent", help: "Expand All", disabled: collapsedIDs.isEmpty) { expandAll() }
                footerButton("list.bullet", help: "Collapse All") { collapseAll() }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
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

    private static let collapseAnimationDuration: Double = 0.15

    private func footerButton(_ icon: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeInOut(duration: Self.collapseAnimationDuration)) { action() } } label: {
            Image(systemName: icon)
                .frame(width: 16)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func expandAll() {
        collapsedIDs.removeAll()
    }

    private func collapseAll() {
        collapsedIDs = Set(headings.filter { hasChildren($0) }.map(\.id))
    }

    private func toggleCollapse(_ heading: Heading) {
        withAnimation(.easeInOut(duration: Self.collapseAnimationDuration)) {
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
