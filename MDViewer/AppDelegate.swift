import AppKit
import ObjectiveC

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let tabbingID = NSWindow.TabbingIdentifier("io.github.ff2248.MDViewer.document")
    private let fileMenuPruner = FileMenuPruner()
    private var windowObserver: Any?
    private var keyMonitor: Any?

    /// Install custom NSDocumentController BEFORE AppKit creates its own.
    /// First instance wins — must be in willFinish, not didFinish.
    func applicationWillFinishLaunching(_: Notification) {
        UserDefaults.registerMDViewerDefaults()
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

        // Defer restore so SwiftUI's DocumentGroup can finish processing any
        // launch-time file argument (e.g. user double-clicked a .md in Finder)
        // first; otherwise the restore loop can race with that document's
        // setup. 400ms is empirical.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard UserDefaults.standard.bool(forKey: SettingsKey.restoreTabsEnabled) else { return }
            for path in TabRestoration.restoredPaths() {
                // `completionHandler: nil` selects the closure-based overload —
                // without it, Swift prefers the `async` variant in this context.
                NSWorkspace.shared.open(
                    [URL(filePath: path)],
                    withApplicationAt: Bundle.main.bundleURL,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
        }
    }

    /// Snapshot open document paths just before termination. We use
    /// `applicationShouldTerminate` rather than `applicationWillTerminate`
    /// because the latter fires after `closeAllDocuments`, by which point
    /// `NSDocumentController.shared.documents` may already be empty.
    /// `.terminateNow` is safe here because our documents are read-only
    /// (`ReadOnlyDocumentController`) so they never carry unsaved changes.
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let paths = NSDocumentController.shared.documents.compactMap(\.fileURL?.path)
        TabRestoration.record(paths: paths)
        return .terminateNow
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
            if window.identifier?.rawValue == WindowID.history {
                window.tabbingMode = .disallowed
                continue
            }
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
