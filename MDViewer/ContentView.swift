import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var headings: [Heading] = []
    @State private var selectedHeadingID: String?
    @State private var sidebarWidth: CGFloat = 240
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
                MarkdownWebView(
                    markdown: appState.markdown,
                    bundle: .main,
                    proxy: webProxy,
                    onHeadingsLoaded: { self.headings = $0 }
                )
            }
            .ignoresSafeArea()
            .onChange(of: appState.markdown) { _ in
                headings = []
                selectedHeadingID = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Drop a .md file here")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("or press ⌘O to open")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - TOC Sidebar

    private var tocSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header with toggle
            HStack {
                Text("Contents")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation { appState.showSidebar = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Heading list
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
        .onChange(of: selectedHeadingID) { id in
            if let id = id {
                webProxy.scrollToHeading(id)
            }
        }
    }

    private var sidebarResizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
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
        case 1: return .headline
        case 2: return .subheadline
        default: return .body
        }
    }
}
