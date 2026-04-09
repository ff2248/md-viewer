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

- **MDViewer/** — SwiftUI app (MDViewerApp, ContentView, MarkdownWebView)
- **Shared/** — Pure logic shared between app and Quick Look extension
- **MDViewerQuickLook/** — Quick Look extension (sandboxed, no ~/Library or external app access)
- **Tests/** — Swift Testing (unit) + XCTest (performance)

Rendering pipeline: `MarkdownParser` (cmark-gfm) → `HighlightRenderer` (JSContext) → `KaTeXRenderer` (JSContext) → WKWebView

## Code Conventions

- **Swift 6** language mode with strict concurrency
- **SwiftFormat** enforced via pre-commit hook (`--swiftversion 6`)
- **@Observable** for AppState (not ObservableObject)
- **NavigationSplitView** for sidebar (not manual HStack)
- **Inspector** for settings panel (not separate Settings window)
- **OSAllocatedUnfairLock** for thread-safe caches (not nonisolated(unsafe) on mutable state)
- **RenderOptions** struct threads all render settings through the pipeline
- **SettingsKey** enum for all UserDefaults key strings
- **LinkRouter** enum for pure link classification logic
- Constants belong in `RenderOptions` (font ranges, markdown extensions, defaults)
- Use `.plain` buttonStyle for sidebar/footer buttons (supports .help() tooltips)
- Use `onTapGesture` instead of `Button` only when preventing click-through is required

## Do NOT

- Use private WebKit APIs (`setValue:forKey:` on WKWebView/preferences) — use public alternatives
- Use `NSApp.sendAction(Selector(...))` for opening Settings — use `@Environment(\.openSettings)` or inspector
- Use `NSWindow.willCloseNotification` observer for app lifecycle — causes issues with input method switching
- Use SwiftUI `Settings { }` scene — creates separate window with lifecycle problems
- Use `.navigationTitle` with `.listStyle(.sidebar)` — causes ghost "Contents" text
- Put `@AppStorage` key strings inline — use `SettingsKey` constants
- Add features beyond what's asked (YAGNI)

## Testing

- **Swift Testing** (`@Test`, `#expect`, `@Suite`) for unit tests
- **XCTest** (`measure {}`) for performance benchmarks only
- Use `options()` helper to build RenderOptions in tests
- Use `testBundle` constant for tests needing bundled resources
- GFM extension tests (strikethrough, footnotes, autolinks) don't work in test target — test manually via `make install` and open test file
- Run `make test` to see coverage percentage

## UI Decisions

- Settings panel uses `.inspector` (inline, non-modal, ⌘, toggle)
- Sidebar collapse/expand via ← → arrow keys (no footer buttons)
- External editor button in toolbar (not menu-only)
- Dynamic window size based on screen (~70% × 75%)
- Sidebar width: fixed ideal 260, user can drag to resize
- Dark mode: CSS `@media (prefers-color-scheme: dark)`, zero Swift code for theme switching
- File watcher: DispatchSource with 100ms debounce, re-creates on rename/delete

## Localization

- README.md (English) uses `docs/screenshot-light-en.png` and `docs/screenshot-dark-en.png`
- README.zh-TW.md (繁體中文) uses `docs/screenshot-light.png` and `docs/screenshot-dark.png`
- Use 台灣繁體中文 conventions, not 中國簡體 (e.g., 按兩下 not 雙擊, 檔案 not 文件)
- Respond in zh-TW when communicating with the user
