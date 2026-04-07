import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
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
                        Task { @MainActor in appState.openFile(url) }
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

                Button("Export as HTML...") {
                    webProxy?.exportHTML(markdown: appState.markdown, title: appState.windowTitle)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
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

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("bodyFontSize") private var bodyFontSize = 16.0
    @AppStorage("codeFontSize") private var codeFontSize = 13.0

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            LabeledContent("Body Font Size") {
                HStack {
                    Slider(value: $bodyFontSize, in: 12...24, step: 1)
                    Text("\(Int(bodyFontSize))px")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            LabeledContent("Code Font Size") {
                HStack {
                    Slider(value: $codeFontSize, in: 10...20, step: 1)
                    Text("\(Int(codeFontSize))px")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .onChange(of: appearance) { _, newValue in
            AppState.applyAppearance(newValue)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.applyAppearance(UserDefaults.standard.string(forKey: "appearance") ?? "auto")
    }
}

// MARK: - App State

@MainActor
@Observable
class AppState {
    var markdown = ""
    var fileURL: URL?
    var windowTitle = "MDViewer"
    var showSidebar = true
    var bodyFontSize: Double = 16
    var codeFontSize: Double = 13

    private var defaultsObserver: Any?

    init() {
        let defaults = UserDefaults.standard
        let savedBody = defaults.double(forKey: "bodyFontSize")
        if savedBody > 0 { bodyFontSize = savedBody }
        let savedCode = defaults.double(forKey: "codeFontSize")
        if savedCode > 0 { codeFontSize = savedCode }

        Self.applyAppearance(defaults.string(forKey: "appearance") ?? "auto")

        // Watch for settings changes from the Settings window
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let d = UserDefaults.standard
            let newBody = d.double(forKey: "bodyFontSize")
            if newBody > 0 { self.bodyFontSize = newBody }
            let newCode = d.double(forKey: "codeFontSize")
            if newCode > 0 { self.codeFontSize = newCode }
        }

        if let path = ProcessInfo.processInfo.arguments.dropFirst().first {
            openFile(URL(fileURLWithPath: path))
        }
    }

    static func applyAppearance(_ value: String) {
        guard let app = NSApp else { return }
        switch value {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
        }
    }

    func openFile(_ url: URL) {
        switch MarkdownRenderer.readMarkdownFile(at: url) {
        case .success(let text):
            markdown = text
            fileURL = url
            windowTitle = url.lastPathComponent
        case .failure:
            markdown = ""
            fileURL = nil
            windowTitle = "MDViewer"
        }
        NSApplication.shared.mainWindow?.title = windowTitle
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
