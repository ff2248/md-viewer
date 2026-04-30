import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.webViewProxy) private var webProxy
    @FocusedValue(\.documentURL) private var documentURL
    @FocusedValue(\.documentText) private var documentText
    @FocusedValue(\.toggleFindBar) private var toggleFindBar
    @State private var globalSettings = GlobalSettings()
    @State private var historyStore = HistoryStore()

    private var canExport: Bool {
        webProxy != nil && documentText?.isEmpty == false
    }

    /// Default window size: ~70% of screen, clamped to reasonable bounds.
    private static var defaultWindowSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let width = min(max(screen.width * 0.7, 900), 1400)
        let height = min(max(screen.height * 0.75, 600), 1000)
        return CGSize(width: width, height: height)
    }

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.$document, globalSettings: globalSettings)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(historyStore)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            globalSettings.showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let url = documentURL {
                                GlobalSettings.openInExternalEditor(url: url)
                            }
                        } label: {
                            Image(systemName: "pencil.and.outline")
                        }
                        .help("Open in External Editor")
                        .disabled(documentURL == nil)
                    }
                }
        }
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Check for Updates...") {
                    UpdateChecker.check()
                }

                Divider()

                Button("Settings...") {
                    globalSettings.showSettings.toggle()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy as Markdown") {
                    webProxy?.copySelectionAsMarkdown()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(webProxy == nil)
            }
            // Note: Do NOT use empty CommandGroup(replacing: .newItem/.saveItem) —
            // causes ghost "NSMenuItem" in menu. Cleanup handled in AppDelegate instead.
            CommandGroup(after: .importExport) {
                Button("Open in External Editor") {
                    if let url = documentURL {
                        GlobalSettings.openInExternalEditor(url: url)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(documentURL == nil)

                Divider()

                Button("Export as PDF...") {
                    webProxy?.exportPDF(title: documentURL?.lastPathComponent ?? "document")
                }
                .keyboardShortcut("e")
                .disabled(!canExport)

                Button("Export as HTML...") {
                    if let text = documentText {
                        webProxy?.exportHTML(markdown: text, title: documentURL?.lastPathComponent ?? "document")
                    }
                }
                .disabled(!canExport)

                Button("Print...") {
                    webProxy?.printContent()
                }
                .keyboardShortcut("p")
                .disabled(!canExport)

                Divider()

                OpenHistoryCommand()
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    toggleFindBar?()
                }
                .keyboardShortcut("f")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Zoom In") { globalSettings.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") { globalSettings.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") { globalSettings.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Window("History", id: WindowID.history) {
            HistoryView()
                .environment(historyStore)
        }
    }
}

// MARK: - Focused Values

struct DocumentURLKey: FocusedValueKey {
    typealias Value = URL
}

struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    var documentURL: URL? {
        get { self[DocumentURLKey.self] }
        set { self[DocumentURLKey.self] = newValue }
    }

    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }
}
