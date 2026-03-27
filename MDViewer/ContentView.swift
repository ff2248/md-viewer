import SwiftUI

struct ContentView: View {
    var appState: AppState
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
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
            }
            .onChange(of: appState.markdown) {
                headings = []
                selectedHeadingID = nil
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

            List(headings, selection: $selectedHeadingID) { heading in
                Text(heading.text)
                    .font(fontForLevel(heading.level))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.leading, CGFloat((heading.level - 1) * 12))
                    .tag(heading.id)
            }
            .listStyle(.sidebar)
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

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .subheadline
        default: .body
        }
    }
}
