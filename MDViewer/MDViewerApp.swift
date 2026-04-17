import ObjectiveC
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
    private static let tabbingID = NSWindow.TabbingIdentifier("io.github.ff2248.MDViewer.document")
    private let fileMenuPruner = FileMenuPruner()
    private var windowObserver: Any?
    private var keyMonitor: Any?

    /// Install custom NSDocumentController BEFORE AppKit creates its own.
    /// First instance wins — must be in willFinish, not didFinish.
    func applicationWillFinishLaunching(_: Notification) {
        _ = ReadOnlyDocumentController()
        NSMenu.installFileMenuDelegateProtection()
    }

    /// Quit the app when the last window is closed. Standard macOS document-based
    /// apps stay open in the Dock, but for a simple viewer this is confusing.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_: Notification) {
        GlobalSettings.applyAppearance(UserDefaults.standard.string(forKey: SettingsKey.appearance) ?? "auto")
        NSWindow.allowsAutomaticWindowTabbing = true

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.tagDocumentWindows()
                self?.attachFileMenuDelegate()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Swallow auto-repeat for shortcuts with ⌘/⌥/⌃ to prevent rapid
            // toggling when a user holds the key. Shift+letter typing is unaffected
            // because .shift alone is excluded from the shortcut modifier set.
            //
            // Whitelist: zoom shortcuts (⌘+/-/=) where repeat is useful.
            // "+" and "=" both appear because macOS reports the physical key differently
            // depending on keyboard layout and shift state.
            if event.isARepeat {
                let shortcutMods: NSEvent.ModifierFlags = [.command, .option, .control]
                let hasShortcutMod = !event.modifierFlags.intersection(shortcutMods).isEmpty
                let chars = event.charactersIgnoringModifiers ?? ""
                let zoomChars: Set = ["+", "-", "="]
                if hasShortcutMod, !zoomChars.contains(chars) {
                    return nil
                }
            }

            // ⌘1–⌘9 tab switching
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command,
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

        // Attach File menu delegate — this is the ONE hook that fires on menu-tracking
        // start (after SwiftUI's re-insertion, before display). Re-attach on activation
        // because SwiftUI may rebuild the submenu.
        attachFileMenuDelegate()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachFileMenuDelegate() }
        }
    }

    private func attachFileMenuDelegate() {
        guard let fileItem = NSApp.mainMenu?.items.first(where: { $0.title == "File" }),
              let submenu = fileItem.submenu else { return }
        if submenu.delegate !== fileMenuPruner {
            fileMenuPruner.previousDelegate = submenu.delegate
            submenu.delegate = fileMenuPruner
        }
    }

    /// Ensure all document windows share a tabbingIdentifier so macOS
    /// automatically merges new windows into the existing tab group.
    private static func tagDocumentWindows() {
        for window in NSApp.windows {
            guard window.isVisible, window.styleMask.contains(.titled),
                  !(window is NSPanel) else { continue }
            window.tabbingMode = .preferred
            window.tabbingIdentifier = tabbingID
        }
    }
}

/// Custom NSDocumentController that disables read-write document commands at the
/// responder-chain validation level. Must be instantiated in applicationWillFinishLaunching.
private final class ReadOnlyDocumentController: NSDocumentController {
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let unwanted: Set<Selector> = [
            Selector(("newDocument:")),
            Selector(("saveDocument:")),
            Selector(("saveDocumentAs:")),
            Selector(("saveDocumentTo:")),
            Selector(("duplicateDocument:")),
            Selector(("renameDocument:")),
            Selector(("moveDocument:")),
            Selector(("revertDocumentToSaved:")),
        ]
        if let action = item.action, unwanted.contains(action) {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// NSMenuDelegate that prunes unwanted items right before the File menu opens.
/// This is the ONLY hook that fires on menu-tracking start, after SwiftUI's
/// re-insertion pass, before AppKit renders the menu. Forwards to SwiftUI's
/// previous delegate so we don't break its behavior.
///
/// Not @MainActor because the swizzled setDelegate hook writes to previousDelegate
/// from a nonisolated context (though AppKit only calls it on main thread).
///
/// Forwards any NSMenuDelegate method we don't explicitly implement to SwiftUI's
/// `AppKitMainMenuItem` via `forwardingTarget(for:)` — otherwise Open Recent,
/// menu validation, and other SwiftUI-managed behaviors would break.
final class FileMenuPruner: NSObject, NSMenuDelegate, @unchecked Sendable {
    nonisolated(unsafe) weak var previousDelegate: NSMenuDelegate?

    static let unwantedTitlePrefixes = [
        "New", "Save", "Duplicate", "Rename", "Move To", "Revert To", "Share",
    ]

    override func forwardingTarget(for _: Selector!) -> Any? {
        previousDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previousDelegate?.responds(to: aSelector) ?? false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        previousDelegate?.menuNeedsUpdate?(menu)
        Self.prune(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        previousDelegate?.menuWillOpen?(menu)
        Self.prune(menu)
    }

    /// Hide items whose title starts with an unwanted prefix, then collapse separator runs.
    /// Exposed for testing.
    static func prune(_ menu: NSMenu) {
        menu.autoenablesItems = false
        for item in menu.items {
            if unwantedTitlePrefixes.contains(where: { item.title.hasPrefix($0) }) {
                item.isHidden = true
                item.isEnabled = false
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
        collapseSeparators(in: menu)
    }

    private static func collapseSeparators(in menu: NSMenu) {
        var prevWasSeparator = true // leading separator → hide
        for item in menu.items where !item.isHidden {
            if item.isSeparatorItem {
                item.isHidden = prevWasSeparator
                prevWasSeparator = true
            } else {
                prevWasSeparator = false
            }
        }
        if let last = menu.items.last(where: { !$0.isHidden }), last.isSeparatorItem {
            last.isHidden = true
        }
    }
}

// MARK: - NSMenu Delegate Protection

/// SwiftUI's DocumentGroup repeatedly resets the File menu's delegate to its own
/// `AppKitMainMenuItem`, bypassing any delegate we install. We swizzle `setDelegate:`
/// on NSMenu so that once our `FileMenuPruner` is installed on a menu titled "File",
/// any attempt to replace it is intercepted: we keep our pruner as the delegate but
/// record the incoming delegate as `previousDelegate` for forwarding.
///
/// Why swizzle? Apple's public APIs cannot remove specific items from the File menu
/// of a DocumentGroup app:
///   - `CommandGroup(replacing: .saveItem) { }` leaves a phantom "NSMenuItem" (FB16145855)
///   - Setting `submenu.delegate = ourPruner` directly is immediately overwritten by
///     SwiftUI's `AppKitMainMenuItem` on every menu update tick
///   - `applicationWillUpdate` + `isHidden = true` is a racy polling approach that
///     loses to SwiftUI's faster re-insertion
/// Swizzling `setDelegate:` is the only reliable way to keep our delegate installed.
/// Precedent: RxSwift swizzles `UITableView.setDelegate:` to solve the same problem
/// (https://github.com/ReactiveX/RxSwift/issues/1755).
extension NSMenu {
    static func installFileMenuDelegateProtection() {
        guard !didInstallSwizzle else { return }
        didInstallSwizzle = true

        let cls: AnyClass = NSMenu.self
        let originalSel = Selector(("setDelegate:"))
        let swizzledSel = #selector(NSMenu.mdv_setDelegate(_:))
        guard let orig = class_getInstanceMethod(cls, originalSel),
              let swiz = class_getInstanceMethod(cls, swizzledSel) else { return }
        method_exchangeImplementations(orig, swiz)
    }

    private nonisolated(unsafe) static var didInstallSwizzle = false

    @objc func mdv_setDelegate(_ newDelegate: NSMenuDelegate?) {
        // AppKit calls setDelegate: on the main thread.
        if title == "File",
           let currentPruner = delegate as? FileMenuPruner,
           !(newDelegate is FileMenuPruner)
        {
            // Intercept: keep our pruner, record incoming delegate for forwarding
            currentPruner.previousDelegate = newDelegate
            return
        }
        // Otherwise, perform the original (swapped) setDelegate
        mdv_setDelegate(newDelegate)
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

    private let defaults: UserDefaults
    private nonisolated(unsafe) var defaultsObserver: Any?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        syncFromDefaults()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.syncFromDefaults() } }
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func syncFromDefaults() {
        let opts = RenderOptions.fromDefaults(defaults)
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
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func zoomOut() {
        bodyFontSize = max(bodyFontSize - 1, RenderOptions.bodyFontSizeRange.lowerBound)
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    func resetZoom() {
        bodyFontSize = RenderOptions.defaults.bodyFontSize
        defaults.set(bodyFontSize, forKey: SettingsKey.bodyFontSize)
    }

    // MARK: - External Editor

    static func openInExternalEditor(url: URL) {
        let editorPath = UserDefaults.standard.string(forKey: SettingsKey.externalEditor) ?? RenderOptions.defaultExternalEditor
        let editorURL = URL(filePath: editorPath)
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
