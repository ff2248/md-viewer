# MDViewer

<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="MDViewer">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg) ![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg) ![Swift](https://img.shields.io/badge/swift-6-F05138.svg) ![License](https://img.shields.io/badge/license-MIT-green.svg)

**極簡、快速的 macOS Markdown 檢視器 — 支援 Quick Look 快速預覽**

按兩下任何 `.md` 檔案即可看到美觀的渲染結果，或在 Finder 中按**空白鍵**即時預覽。沒有編輯器的負擔、不用設定、不用等待。專心閱讀就好。

繁體中文 | [English](README.md)

</div>

---

## 截圖

<div align="center">

**淺色模式** — GitHub 風格渲染搭配目錄側邊欄
<img src="docs/screenshot-light.png" alt="MDViewer 淺色模式" width="800">

**深色模式** — 自動跟隨系統外觀切換
<img src="docs/screenshot-dark.png" alt="MDViewer 深色模式" width="800">

</div>

---

## 功能

- **GitHub 風格渲染** — 標題、表格、任務清單、刪除線、引用區塊
- **語法高亮** — 透過 highlight.js 支援常見程式語言
- **數學公式** — `$...$` 行內、`$$...$$` 區塊、` ```math ` 程式碼區塊（KaTeX）
- **Mermaid 圖表** — 流程圖、序列圖等（延遲載入）
- **腳註** — `[^1]` 語法，支援可點擊的回溯連結
- **Emoji 短碼** — `:rocket:` → 🚀
- **Quick Look** — 在 Finder 中選取 `.md` 按空白鍵即可預覽，支援內嵌本地圖片
- **目錄側邊欄** — 可收合的標題導覽，點擊即跳轉
- **匯出** — 儲存為 PDF 或獨立 HTML，或透過系統列印對話框列印
- **CJK 支援** — 完整 UTF-8，支援中文、日文、韓文
- **離線使用** — 所有相依套件皆已打包，零網路請求

---

## 鍵盤快捷鍵

| 快捷鍵 | 功能 |
|---|---|
| ⌘O | 開啟檔案 |
| ⇧⌘E | 以外部編輯器開啟 |
| ⌘E | 匯出為 PDF |
| ⌘P | 列印 |
| ⌘, | 切換設定面板 |
| ⇧⌘S | 切換目錄側邊欄 |
| ← / → | 收合 / 展開目錄標題 |
| ⌘+ / ⌘− | 放大 / 縮小 |
| ⌘0 | 實際大小 |
| 空白鍵（Finder 中） | Quick Look 預覽 |

---

## 安裝

### 前置需求

- macOS 14.0（Sonoma）或更新版本
- Xcode Command Line Tools（`xcode-select --install`）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

### 一鍵安裝

```bash
git clone https://github.com/ff2248/md-viewer.git
cd md-viewer
make install
```

完成。`make install` 會自動編譯、複製到 `/Applications`、並啟用 Quick Look 擴充功能。

> 首次啟動時，macOS 可能會阻擋此應用程式。請前往**系統設定 → 隱私權與安全性 → 仍要打開**以允許執行。

### 其他開啟方式

| 方式 | 操作 |
|---|---|
| 按兩下開啟 | 開啟任意 `.md` 檔案（設為預設後） |
| 拖放 | 將 `.md` 檔案拖放到應用程式視窗 |
| 命令列 | `open -a MDViewer yourfile.md` |

### 設為預設檢視器

在任意 `.md` 檔案上按右鍵 → **取得資訊** → **打開檔案的應用程式** → 選擇 **MDViewer** → **全部更改**。

---

## 架構

```
MDViewer/                              # SwiftUI 主應用程式
├── MDViewerApp.swift                  # 應用程式進入點、選單指令、檔案處理
├── ContentView.swift                  # 主版面配置與目錄側邊欄
└── MarkdownWebView.swift              # WKWebView 代理、PDF/HTML 匯出、列印

MDViewerQuickLook/                     # Quick Look 擴充功能（沙盒化）
└── PreviewViewController.swift        # 以獨立 HTML 回傳 QLPreviewReply

Shared/                                # 主程式與擴充功能共用
├── MarkdownParser.swift               # cmark-gfm 解析器，啟用 GFM 擴充 + 腳註
├── MarkdownRenderer.swift              # 檔案 I/O、HTML 組裝、本地圖片內嵌
├── HighlightRenderer.swift            # 透過 JavaScriptCore 執行語法高亮
├── KaTeXRenderer.swift                # 透過 JavaScriptCore 執行數學渲染
├── RenderOptions.swift                # 共用設定常數與渲染選項
├── LinkRouter.swift                   # 連結點擊分類與路由
├── JSContextCache.swift               # 執行緒安全的延遲 JSContext 快取
├── StringExtensions.swift             # Emoji 短碼、HTML 跳脫/反跳脫、JS 跳脫
└── Resources/
    ├── template.html                  # HTML 範本與 JS bridge + heading slug
    ├── custom.css                     # 共用版面樣式（單一來源）
    ├── highlight.min.js               # 語法高亮引擎
    ├── katex.min.js                   # 數學渲染引擎
    ├── mermaid.min.js                 # 圖表渲染（延遲載入）
    ├── github-markdown.css            # GitHub 風格文件樣式（淺色 + 深色）
    ├── github.min.css                 # 語法主題（淺色）
    ├── github-dark.min.css            # 語法主題（深色）
    └── katex.min.css                  # 數學樣式與字型
```

### 運作原理

**主應用程式**在 Swift 中透過 cmark-gfm 將 Markdown 解析為 HTML，再透過 JavaScriptCore 預先渲染語法高亮與數學公式，最後將結果注入預載的 WKWebView。瀏覽器中不執行 JavaScript，唯一例外是 Mermaid（需要 DOM）。

**Quick Look 擴充功能**使用 `QLPreviewReply` 資料驅動 API，回傳內嵌所有 JS/CSS 的獨立 HTML 讓系統渲染。

---

## 貢獻

```bash
make test      # 執行測試
make format    # 格式化 Swift 程式碼（需安裝：brew install swiftformat）
```

## 授權條款

[MIT](LICENSE) — 打包的第三方相依套件授權請參閱 [ThirdPartyNotices.txt](ThirdPartyNotices.txt)。
