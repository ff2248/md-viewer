import SwiftUI

struct ContentView: View {
    var appState: AppState
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var collapsedIDs: Set<String> = []
    @State private var sidebarWidth: CGFloat = 240
    @State private var isCursorPushed = false
    @GestureState private var dragOffset: CGFloat = 0
    @StateObject private var webProxy = WebViewProxy()
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if appState.markdown.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                if appState.showSidebar {
                    tocSidebar
                    Divider()
                }
                MarkdownWebView(proxy: webProxy, markdown: appState.markdown)
                    .ignoresSafeArea()
            }
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

    private var tocSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contents")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { appState.showSidebar = false }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Hide Sidebar")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider()

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
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { expandAll() } } label: {
                    Image(systemName: "list.bullet.indent")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(collapsedIDs.isEmpty)
                .help("Expand All")

                Button { withAnimation(.easeInOut(duration: 0.15)) { collapseAll() } } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Collapse All")

                Spacer()

                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: max(160, min(sidebarWidth + dragOffset, 500)))
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
        .onChange(of: selectedHeadingID) { _, newValue in
            if let id = newValue {
                webProxy.scrollToHeading(id)
            }
        }
    }

    private var sidebarResizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !isCursorPushed {
                    NSCursor.resizeLeftRight.push()
                    isCursorPushed = true
                } else if !hovering && isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        sidebarWidth = max(160, min(sidebarWidth + value.translation.width, 500))
                    }
            )
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
