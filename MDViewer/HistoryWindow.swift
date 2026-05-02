import AppKit
import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var store
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var query = ""
    @State private var showClearConfirm = false
    @State private var sawDocumentWindow = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
        .alert("Clear All History?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { store.clear() }
        } message: {
            Text("This removes every entry from your history. This action cannot be undone.")
        }
        // Auto-dismiss when the user closes their last document window.
        // SwiftUI DocumentGroup doesn't call NSDocumentController.removeDocument,
        // so we monitor NSApp.windows directly. Only dismiss after we've seen
        // at least one document window — otherwise History opened first (before
        // any document) would close itself immediately.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUpdateNotification)) { _ in
            let hasVisibleDoc = NSApp.windows.contains { window in
                window.isVisible
                    && window.styleMask.contains(.titled)
                    && !(window is NSPanel)
                    && window.identifier?.rawValue != WindowID.history
            }
            if hasVisibleDoc {
                if !sawDocumentWindow { sawDocumentWindow = true }
            } else if sawDocumentWindow {
                dismissWindow(id: WindowID.history)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(8)
    }

    private var list: some View {
        let filtered = store.filtered(query: query)
        return Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No History" : "No Matches",
                    systemImage: "clock",
                    description: Text(query.isEmpty ? "Files you open will appear here." : "Try a different search term.")
                )
            } else {
                List(filtered, id: \.self) { path in
                    Button {
                        open(path)
                    } label: {
                        HistoryRow(path: path)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open") { open(path) }
                        Button("Reveal in Finder") { revealInFinder(path) }
                        Divider()
                        Button("Remove from History", role: .destructive) {
                            store.remove(path)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Clear All…") { showClearConfirm = true }
                .disabled(store.entries.isEmpty)
        }
        .padding(8)
    }

    private func open(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            store.remove(path)
            let alert = NSAlert()
            alert.messageText = "File no longer exists"
            alert.informativeText = path
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(
            [URL(filePath: path)],
            withApplicationAt: Bundle.main.bundleURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            // User-initiated open — surface a launch error (permission,
            // sandbox, corrupted file) instead of failing silently. Marshal
            // to main actor since the completion runs on a background queue.
            if let error {
                Task { @MainActor in NSAlert(error: error).runModal() }
            }
        }
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }
}

struct HistoryRow: View {
    let path: String

    private var filename: String {
        URL(filePath: path).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(filename)
                .font(.body)
                .fontWeight(.medium)
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}

struct OpenHistoryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show History…") { openWindow(id: WindowID.history) }
            .keyboardShortcut("y", modifiers: .command)
    }
}
