# MDViewer

<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="MDViewer">

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg) ![Swift](https://img.shields.io/badge/swift-6-F05138.svg) ![License](https://img.shields.io/badge/license-MIT-green.svg)

**A minimal, native macOS Markdown viewer with Quick Look — fast, offline, free**

Double-click any `.md` file for a beautifully rendered preview, or press **Space** in Finder for instant Quick Look. GitHub-flavored Markdown, math, and Mermaid — all rendered natively. No editor overhead, no setup, no network. Just read.

[繁體中文](README.zh-TW.md) | English

</div>

---

## Screenshots

<div align="center">

**Main window** — GitHub-style rendering with TOC sidebar, automatic light / dark theme

<table>
<tr>
<td><img src="docs/screenshot-light-en.png" alt="MDViewer rendering a Markdown document in light mode on macOS, with TOC sidebar and syntax highlighting"></td>
<td><img src="docs/screenshot-dark-en.png" alt="MDViewer Markdown preview in dark mode on macOS, following system appearance"></td>
</tr>
</table>

**Quick Look** — press Space on any `.md` file in Finder for an instant preview
<img src="docs/screenshot-quicklook-en.png" alt="MDViewer Quick Look preview of a Markdown document in Finder, showing rendered headings, syntax-highlighted code, table, blockquote, and math formula" width="600">

</div>

---

## Who is this for?

macOS has no built-in way to read Markdown — open a `.md` file in Preview and you'll see raw text. MDViewer fills that gap: a native, focused reader that renders `.md` beautifully when you double-click a file or press Space in Finder.

**Similar tools:**
- **Just need Quick Look?** [QLMarkdown](https://github.com/sbarex/QLMarkdown) is an open-source Quick Look extension. MDViewer includes Quick Look too, plus a standalone reader window with TOC sidebar, find-in-page, PDF/HTML export, and zoom.
- **Writing Markdown?** Try [Obsidian](https://obsidian.md), [Typora](https://typora.io), [iA Writer](https://ia.net/writer), [MacDown](https://macdown.uranusjr.com), or [VS Code](https://code.visualstudio.com). Keep MDViewer as your default `.md` viewer, pick any of them as your external editor inside MDViewer, and press ⇧⌘E to open the current file there — MDViewer live-refreshes when you save.

---

## Features

- **GitHub-style rendering** — headings, tables, task lists, strikethrough, blockquotes
- **Syntax highlighting** — common languages via highlight.js
- **Math formulas** — `$...$` inline, `$$...$$` display, and ` ```math ` code blocks via Temml (MathML)
- **Mermaid diagrams** — flowcharts, sequence diagrams, etc. (lazy-loaded)
- **Footnotes** — `[^1]` syntax with clickable back-references
- **Emoji shortcodes** — `:rocket:` → 🚀
- **Quick Look** — press Space in Finder to preview any `.md` file, with inline local images
- **TOC sidebar** — collapsible heading navigation with click-to-scroll
- **In-page find** — ⌘F opens a find bar with match highlighting and next/previous navigation
- **Export** — save as PDF or self-contained HTML (all JS/CSS inlined), or print via system dialog
- **Copy as Markdown** — right-click or ⇧⌘C copies the original Markdown source of the current selection (block-level granularity); pastes cleanly into GitHub, Slack, or any Markdown editor. Empty selection is a no-op.
- **Code block copy** — every rendered code block has a one-click copy button in its corner
- **Check for updates** — menu item that compares against the latest GitHub release
- **CJK support** — full UTF-8 including Chinese, Japanese, Korean
- **Offline** — all dependencies bundled, zero network requests (except manual update check)

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘O | Open file dialog |
| ⇧⌘E | Open in external editor |
| ⌘E | Export as PDF |
| ⌘P | Print |
| ⇧⌘C | Copy selection as Markdown |
| ⌘F | Find in page |
| ⌘, | Toggle settings panel |
| ⇧⌘S | Toggle TOC sidebar |
| ← / → | Collapse / expand TOC heading |
| ⌘+ / ⌘− | Zoom in / out |
| ⌘0 | Actual size |
| Space (in Finder) | Quick Look preview |

---

## Install

### Homebrew (recommended)

```bash
brew tap ff2248/mdviewer
brew install --cask mdviewer
```

### Build from source

Requires macOS 14+, Xcode 16+, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ff2248/md-viewer.git
cd md-viewer
make install
```

Both methods install to `/Applications` and enable the Quick Look extension.

### Troubleshooting first launch

MDViewer is currently distributed with ad-hoc signing — it is not enrolled in the Apple Developer Program and therefore not notarized, so Gatekeeper blocks it on first launch. Since macOS Sequoia the right-click "Open" bypass no longer works, so pick one of the following:

- **System Settings (recommended)**: open **System Settings → Privacy & Security**, scroll to the Security section, click **Open Anyway**, then confirm with your password.
- **Terminal one-liner**: `xattr -dr com.apple.quarantine /Applications/MDViewer.app`

### Upgrade

```bash
# Homebrew
brew upgrade mdviewer

# Built from source
git pull
make install
```

### Uninstall

```bash
# Homebrew
brew uninstall mdviewer

# Built from source
make uninstall
```

### Other ways to open files

| Method | How |
|---|---|
| Double-click | Open any `.md` file (after setting as default) |
| Drag & drop | Drop a `.md` file onto the app window |
| CLI | `open -a MDViewer yourfile.md` |

### Set as default viewer

Right-click any `.md` file → **Get Info** → **Open With** → select **MDViewer** → **Change All**.

---

## How it works

**Main app** parses Markdown to HTML via cmark-gfm in Swift, pre-renders syntax highlighting (highlight.js) and math (Temml → MathML) via JavaScriptCore, then injects the result into a pre-loaded WKWebView. No JavaScript runs in the browser except Mermaid, which requires DOM.

**Quick Look extension** uses the `QLPreviewReply` data-based API — it returns self-contained HTML with all JS/CSS inlined for the system to render inside its sandbox.

The `Shared/` directory holds the rendering pipeline and web resources used by both the app and the Quick Look extension, so previews and the main window stay visually identical.

---

## Contributing

```bash
make test      # Run tests
make format    # Format Swift code (requires: brew install swiftformat)
```

## License

[MIT](LICENSE) — see [ThirdPartyNotices.txt](ThirdPartyNotices.txt) for bundled dependencies.
