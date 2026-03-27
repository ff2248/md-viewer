import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @FocusedValue(\.webViewProxy) private var webProxy

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onOpenURL { url in
                    appState.openFile(url)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url = url else { return }
                        DispatchQueue.main.async { appState.openFile(url) }
                    }
                    return true
                }
        }
        .defaultSize(width: 1000, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") { appState.showOpenPanel() }
                    .keyboardShortcut("o")

                Divider()

                Button("Export as PDF...") {
                    webProxy?.exportPDF(title: appState.windowTitle)
                }
                .keyboardShortcut("e")
                .disabled(webProxy == nil || appState.markdown.isEmpty)

                Button("Print...") {
                    webProxy?.printContent()
                }
                .keyboardShortcut("p")
                .disabled(webProxy == nil || appState.markdown.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button(appState.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation { appState.showSidebar.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var markdown = ""
    @Published var windowTitle = "MDViewer"
    @Published var showSidebar = true

    init() {
        if let path = ProcessInfo.processInfo.arguments.dropFirst().first {
            openFile(URL(fileURLWithPath: path))
        }
    }

    func openFile(_ url: URL) {
        switch MarkdownRenderer.readMarkdownFile(at: url) {
        case .success(let text):
            markdown = text
            windowTitle = url.lastPathComponent
        case .failure:
            markdown = ""
            windowTitle = "MDViewer"
        }
        DispatchQueue.main.async {
            NSApplication.shared.mainWindow?.title = self.windowTitle
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            openFile(url)
        }
    }
}
