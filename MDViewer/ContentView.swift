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
            }
            .ignoresSafeArea()
            .onAppear {
                webProxy.onHeadingsLoaded = { self.headings = $0 }
                webProxy.fileURL = appState.fileURL
            }
            .onChange(of: appState.fileURL) {
                webProxy.fileURL = appState.fileURL
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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

            HStack(spacing: 4) {
                TooltipButton(icon: "list.bullet.indent", tooltip: "Expand All", isDisabled: collapsedIDs.isEmpty) {
                    withAnimation(.easeInOut(duration: 0.15)) { expandAll() }
                }
                .frame(width: 24, height: 24)

                TooltipButton(icon: "list.bullet", tooltip: "Collapse All") {
                    withAnimation(.easeInOut(duration: 0.15)) { collapseAll() }
                }
                .frame(width: 24, height: 24)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Tooltip Button

    private struct TooltipButton: NSViewRepresentable {
        let icon: String
        let tooltip: String
        var isDisabled: Bool = false
        let action: () -> Void

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton()
            button.isBordered = false
            button.target = context.coordinator
            button.action = #selector(Coordinator.clicked)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .vertical)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return button
        }

        func updateNSView(_ button: NSButton, context: Context) {
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip)
            button.toolTip = tooltip
            button.isEnabled = !isDisabled
            button.alphaValue = isDisabled ? 0.3 : 1
            context.coordinator.action = action
        }

        func makeCoordinator() -> Coordinator { Coordinator(action: action) }

        class Coordinator: NSObject {
            var action: () -> Void
            init(action: @escaping () -> Void) { self.action = action }
            @objc func clicked() { action() }
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
