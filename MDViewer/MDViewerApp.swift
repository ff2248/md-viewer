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

    private var canExport: Bool {
        webProxy != nil && !appState.markdown.isEmpty
    }

    /// Default window size: ~70% of screen, clamped to reasonable bounds.
    private static var defaultWindowSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let width = min(max(screen.width * 0.7, 900), 1400)
        let height = min(max(screen.height * 0.75, 600), 1000)
        return CGSize(width: width, height: height)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(appState.windowTitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.openInExternalEditor()
                        } label: {
                            Image(systemName: "pencil.and.outline")
                        }
                        .help("Open in External Editor")
                        .disabled(appState.fileURL == nil)
                    }
                }
                .onOpenURL { url in
                    appState.openFile(url)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in appState.openFile(url) }
                    }
                    return true
                }
        }
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    appState.showSettings.toggle()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open...") { appState.showOpenPanel() }
                    .keyboardShortcut("o")

                Divider()

                Button("Open in External Editor") {
                    appState.openInExternalEditor()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.fileURL == nil)

                Divider()

                Button("Export as PDF...") {
                    webProxy?.exportPDF(title: appState.windowTitle)
                }
                .keyboardShortcut("e")
                .disabled(!canExport)

                Button("Export as HTML...") {
                    webProxy?.exportHTML(markdown: appState.markdown, title: appState.windowTitle)
                }
                .disabled(!canExport)

                Button("Print...") {
                    webProxy?.printContent()
                }
                .keyboardShortcut("p")
                .disabled(!canExport)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    withAnimation {
                        switch appState.columnVisibility {
                        case .detailOnly: appState.columnVisibility = .doubleColumn
                        default: appState.columnVisibility = .detailOnly
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Zoom In") { appState.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") { appState.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") { appState.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = "auto"
    @AppStorage(SettingsKey.hardBreaks) private var hardBreaks = RenderOptions.defaults.hardBreaks
    @AppStorage(SettingsKey.showFrontMatter) private var showFrontMatter = RenderOptions.defaults.showFrontMatter
    @AppStorage(SettingsKey.externalEditor) private var externalEditor = RenderOptions.defaultExternalEditor
    @AppStorage(SettingsKey.bodyFontSize) private var bodyFontSize = RenderOptions.defaults.bodyFontSize
    @AppStorage(SettingsKey.codeFontSize) private var codeFontSize = RenderOptions.defaults.codeFontSize

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            Toggle("Single newline as line break", isOn: $hardBreaks)
            Toggle("Show YAML front matter", isOn: $showFrontMatter)

            LabeledContent("External Editor") {
                HStack {
                    Text(editorDisplayName)
                    Spacer()
                    Button("Choose...") { pickEditor() }
                }
            }

            LabeledContent("Body Font Size") {
                HStack {
                    Slider(value: $bodyFontSize, in: RenderOptions.bodyFontSizeRange, step: 1)
                    Text("\(Int(bodyFontSize))px")
                        .monospacedDigit()
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }

            LabeledContent("Code Font Size") {
                HStack {
                    Slider(value: $codeFontSize, in: RenderOptions.codeFontSizeRange, step: 1)
                    Text("\(Int(codeFontSize))px")
                        .monospacedDigit()
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            AppState.applyAppearance(newValue)
        }
    }

    private var editorDisplayName: String {
        let url = URL(filePath: externalEditor)
        return url.deletingPathExtension().lastPathComponent
    }

    private func pickEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an application to edit Markdown files"
        if panel.runModal() == .OK, let url = panel.url {
            externalEditor = url.path
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppState.applyAppearance(UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "auto")
    }
}

// MARK: - App State

@MainActor
@Observable
class AppState {
    var markdown = ""
    var fileURL: URL?
    var windowTitle = "MDViewer"
    var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    var showSettings = false
    var hardBreaks: Bool = RenderOptions.defaults.hardBreaks
    var showFrontMatter: Bool = RenderOptions.defaults.showFrontMatter
    var bodyFontSize: Double = RenderOptions.defaults.bodyFontSize
    var codeFontSize: Double = RenderOptions.defaults.codeFontSize

    var renderOptions: RenderOptions {
        RenderOptions(hardBreaks: hardBreaks, showFrontMatter: showFrontMatter,
                      bodyFontSize: bodyFontSize, codeFontSize: codeFontSize)
    }

    private var defaultsObserver: Any?
    private var fileWatcher: DispatchSourceFileSystemObject?

    init() {
        syncFromDefaults()
        Self.applyAppearance(UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "auto")

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.syncFromDefaults() }

        if let path = ProcessInfo.processInfo.arguments.dropFirst().first {
            openFile(URL(fileURLWithPath: path))
        }
    }

    private func syncFromDefaults() {
        let opts = RenderOptions.fromDefaults()
        hardBreaks = opts.hardBreaks
        showFrontMatter = opts.showFrontMatter
        bodyFontSize = opts.bodyFontSize
        codeFontSize = opts.codeFontSize
    }

    static func applyAppearance(_ value: String) {
        guard let app = NSApp else { return }
        switch value {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: app.appearance = nil
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        bodyFontSize = min(bodyFontSize + 1, RenderOptions.bodyFontSizeRange.upperBound)
        UserDefaults.standard.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func zoomOut() {
        bodyFontSize = max(bodyFontSize - 1, RenderOptions.bodyFontSizeRange.lowerBound)
        UserDefaults.standard.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func resetZoom() {
        bodyFontSize = RenderOptions.defaults.bodyFontSize
        UserDefaults.standard.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    // MARK: - File Operations

    func openFile(_ url: URL) {
        switch MarkdownRenderer.readMarkdownFile(at: url) {
        case let .success(text):
            markdown = text
            fileURL = url
            windowTitle = url.lastPathComponent
            watchFile(url)
        case .failure:
            markdown = ""
            fileURL = nil
            windowTitle = "MDViewer"
            fileWatcher?.cancel()
            fileWatcher = nil
        }
    }

    func openInExternalEditor() {
        guard let url = fileURL else { return }
        let editorPath = UserDefaults.standard.string(forKey: SettingsKey.externalEditor) ?? RenderOptions.defaultExternalEditor
        let editorURL = URL(filePath: editorPath)
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
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

    // MARK: - File Watcher

    private func watchFile(_ url: URL) {
        fileWatcher?.cancel()
        fileWatcher = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if case let .success(text) = MarkdownRenderer.readMarkdownFile(at: url) {
                    self.markdown = text
                }
                self.watchFile(url)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }
}
