# MDViewer - Claude Code Instructions

## Project Overview

A minimal macOS Markdown viewer with Quick Look support. SwiftUI + WKWebView, Swift 6, macOS 14+.

## Requirements

Xcode 16+ with Swift 6. Project generated from `project.yml` via xcodegen.

## Build Commands

```bash
make install    # Build + install to /Applications + register with LaunchServices
make test       # Run tests with coverage report
make format     # SwiftFormat (auto-runs on pre-commit hook)
```

Do NOT use raw `xcodebuild` commands — always use `make install` for building and installing.

## Architecture

- **MDViewer/** — SwiftUI DocumentGroup app
  - `MDViewerApp.swift` — App entry, DocumentGroup, menu commands, GlobalSettings
  - `MarkdownDocument.swift` — FileDocument (read-only, per-window)
  - `ContentView.swift` — NavigationSplitView with TOC sidebar
  - `MarkdownWebView.swift` — WKWebView proxy, PDF/HTML export, link routing
- **Shared/** — Pure logic shared between app and Quick Look extension
  - `RenderOptions.swift` — Settings constants (SettingsKey, font ranges, defaults)
  - `LinkRouter.swift` — Pure link classification (external/relative/ignored)
- **MDViewerQuickLook/** — Quick Look extension (sandboxed, no ~/Library or external app access)
- **Tests/** — Swift Testing (unit) + XCTest (performance)

Rendering pipeline: `MarkdownParser` (cmark-gfm + `MathExtractor` AST walk for inline `$...$`) → `HighlightRenderer` (JSContext) → `MathRenderer` (Temml; post-HTML pass for `$$...$$` and ` ```math `) → WKWebView

### Multi-Window / Tab Architecture

- `DocumentGroup(viewing: MarkdownDocument.self)` — each window has its own document
- `GlobalSettings` — shared across all windows (appearance, font sizes, render options)
- Tabs work via `NSWindow.allowsAutomaticWindowTabbing = true` (set in AppDelegate)
- `open -a MDViewer file.md` opens in new tab ✅
- Sidebar drag & drop opens in new tab ✅ (uses `NSWorkspace.shared.open` → Apple Event path)
- Content area drag & drop blocked by WKWebView (known limitation, cannot fix)

## Code Conventions

- **Swift 6** language mode with strict concurrency
- **SwiftFormat** enforced via pre-commit hook (`--swiftversion 6`)
- **@Observable** for GlobalSettings (not ObservableObject)
- **DocumentGroup** for multi-window (not WindowGroup with shared AppState)
- **NavigationSplitView** for sidebar (not manual HStack)
- **Inspector** for settings panel (not separate Settings window)
- **OSAllocatedUnfairLock** for thread-safe caches (not nonisolated(unsafe) on mutable state)
- **RenderOptions** struct threads all render settings through the pipeline
- **SettingsKey** enum for all UserDefaults key strings
- **LinkRouter** enum for pure link classification logic
- Constants belong in `RenderOptions` (font ranges, markdown extensions, defaults)

## Do NOT

- Use private WebKit APIs (`setValue:forKey:` on WKWebView/preferences) — use public alternatives (`underPageBackgroundColor`, `loadFileURL`)
- Use `NSWindow.willCloseNotification` observer for app lifecycle — causes issues with input method switching
- Use SwiftUI `Settings { }` scene — creates separate window with lifecycle problems
- Use `.navigationTitle` with `.listStyle(.sidebar)` — causes ghost "Contents" text on resize
- Put `@AppStorage` key strings inline — use `SettingsKey` constants
- Try to intercept drag & drop on WKWebView content area — internal private subviews consume drag events, `unregisterDraggedTypes()` and `registerForDraggedTypes` override do not work, glass pane overlay with `hitTest` nil also fails
- Use `NSDocumentController.shared.openDocument(display:)` to open files from within the app — bypasses macOS automatic tab merging; use `NSWorkspace.shared.open` (Apple Event path) instead
- Use empty `CommandGroup(replacing: .newItem/.saveItem) { }` — causes ghost "NSMenuItem" text in menu (SwiftUI bug FB16145855)
- Rely on `applicationWillUpdate` or `didBecomeActive` to modify File menu items — SwiftUI's `AppKitMainMenuItem` repeatedly resets the delegate. Must swizzle `NSMenu.setDelegate:` to prevent SwiftUI from clobbering a custom `FileMenuPruner` delegate, then install via `applicationWillFinishLaunching` (see `MDViewerApp.swift`)
- Add features beyond what's asked (YAGNI)

## Known Issues / TODO

- **Content area drop blocked by WKWebView** — accepted limitation, cannot fix without Apple API changes

## Testing

- **Swift Testing** (`@Test`, `#expect`, `@Suite`) for unit tests
- **XCTest** (`measure {}`) for performance benchmarks only
- Use `options()` helper to build RenderOptions in tests
- Use `testBundle` constant for tests needing bundled resources
- GFM extension tests (strikethrough, footnotes, autolinks) don't work in test target — test manually via `make install` and open test file
- Run `make test` to see coverage percentage (currently ~45%)

## UI Decisions

- Settings panel uses `.inspector` (inline, non-modal, ⌘, toggle)
- Sidebar collapse/expand via ← → arrow keys (no footer buttons)
- External editor button in toolbar
- Dynamic window size based on screen (~70% × 75%)
- Sidebar width: fixed ideal 260, user can drag to resize
- Dark mode: CSS `@media (prefers-color-scheme: dark)`, zero Swift code for theme switching
- Sidebar fonts: H1 bold, H2+ regular, all `.body` size, differentiated by weight + indentation
- Default font sizes: body 15px, code 12px

## Localization

- README.md (English) uses `docs/screenshot-light-en.png` and `docs/screenshot-dark-en.png`
- README.zh-TW.md (繁體中文) uses `docs/screenshot-light.png` and `docs/screenshot-dark.png`
- Use 台灣繁體中文 conventions, not 中國簡體 (e.g., 按兩下 not 雙擊, 檔案 not 文件)
- Respond in zh-TW when communicating with the user
