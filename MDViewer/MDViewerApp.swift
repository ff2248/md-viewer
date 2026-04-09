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
    @State private var globalSettings = GlobalSettings()

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
                Button("Settings...") {
                    globalSettings.showSettings.toggle()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                // DocumentGroup provides Open... automatically
            }
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
            }
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Zoom In") { globalSettings.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") { globalSettings.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") { globalSettings.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
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
            GlobalSettings.applyAppearance(newValue)
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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let tabbingID = NSWindow.TabbingIdentifier("com.local.MDViewer.document")
    private var windowObserver: Any?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_: Notification) {
        GlobalSettings.applyAppearance(UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "auto")
        NSWindow.allowsAutomaticWindowTabbing = true

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { Self.tagDocumentWindows() } }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let chars = event.charactersIgnoringModifiers,
                  let digit = chars.first?.wholeNumberValue,
                  digit >= 1, digit <= 9,
                  let tabs = NSApp.keyWindow?.tabbedWindows,
                  tabs.count > 1 else { return event }
            let index = digit == 9 ? tabs.count - 1 : digit - 1
            guard index < tabs.count else { return event }
            tabs[index].makeKeyAndOrderFront(nil)
            return nil
        }
    }

    /// Ensure all document windows share a tabbingIdentifier so macOS
    /// automatically merges new windows into the existing tab group.
    /// Idempotent — safe to call on every focus change.
    private static func tagDocumentWindows() {
        for window in NSApp.windows {
            guard window.isVisible, window.styleMask.contains(.titled),
                  !(window is NSPanel) else { continue }
            window.tabbingMode = .preferred
            window.tabbingIdentifier = tabbingID
        }
    }
}

// MARK: - Global Settings (shared across all windows)

@MainActor
@Observable
class GlobalSettings {
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

    init() {
        syncFromDefaults()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.syncFromDefaults() } }
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

    // MARK: - External Editor

    static func openInExternalEditor(url: URL) {
        let editorPath = UserDefaults.standard.string(forKey: SettingsKey.externalEditor) ?? RenderOptions.defaultExternalEditor
        let editorURL = URL(filePath: editorPath)
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
