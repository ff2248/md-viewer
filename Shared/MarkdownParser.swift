import CMarkGFM
import Foundation

/// Converts Markdown text to HTML using GitHub's cmark-gfm parser.
///
/// Supports GFM extensions: tables, task lists, strikethrough, autolinks, tagfilter.
/// Pre-processes: YAML front matter stripping, emoji shortcode replacement.
/// Runs natively in Swift (no JavaScript) for fast, authoritative GFM rendering.
enum MarkdownParser {
    /// Parse Markdown to HTML with all GFM extensions enabled.
    /// Raw HTML is allowed; dangerous tags are filtered by GFM tagfilter.
    ///
    /// `data-sourcepos` line numbers in the returned HTML always refer to
    /// the *emoji-replaced original* (i.e. the value `preprocess` returns),
    /// regardless of whether the source had YAML front matter. This keeps
    /// "Copy as Markdown" working for selections that cover the synthetic
    /// front-matter table, the body, or both.
    static func toHTML(_ markdown: String, options: RenderOptions = .defaults, mathRender: MathRenderClosure? = nil) -> String {
        // Emoji first (doesn't move line boundaries); then front-matter strip
        // (which does), so we capture the original-space offset before cmark.
        var text = replaceEmojiShortcodes(markdown)
        let meta = extractFrontMatterWithMeta(&text)
        let offset = meta.map { $0.firstBodyLine - 1 } ?? 0
        var html = cmarkToHTML(text, hardBreaks: options.hardBreaks, mathRender: mathRender)
        if offset > 0 {
            html = offsetSourcepos(in: html, by: offset)
        }
        if options.showFrontMatter, let tableHTML = meta?.html {
            html = tableHTML + html
        }
        return html
    }

    /// Returns the Markdown after emoji-shortcode replacement, with YAML
    /// front matter preserved in place. Line numbers in `toHTML`'s emitted
    /// `data-sourcepos` attributes refer to this value's lines, so any
    /// feature that maps rendered output back to Markdown source
    /// (e.g. "Copy as Markdown") slices from here.
    static func preprocess(_ markdown: String, options _: RenderOptions = .defaults) -> String {
        replaceEmojiShortcodes(markdown)
    }

    /// Extracts 1-based inclusive line range `[startLine, endLine]` from `text`.
    /// Returns `nil` for out-of-range, zero/negative, or inverted inputs.
    static func extractLines(_ text: String, startLine: Int, endLine: Int) -> String? {
        guard startLine >= 1, endLine >= startLine else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard endLine <= lines.count else { return nil }
        return lines[(startLine - 1) ... (endLine - 1)].joined(separator: "\n")
    }

    // MARK: - Pre-processing

    struct FrontMatterMeta {
        /// Rendered `<table>` HTML (already tagged with original-space
        /// `data-sourcepos`), or nil if no recognisable `key: value` rows.
        let html: String?
        /// 1-based line number of the closing `---` in the original text.
        let closeLine: Int
        /// 1-based line number where body content resumes in the original
        /// text, after any blank lines following the closing `---`.
        let firstBodyLine: Int
    }

    /// Extracts YAML front matter and returns metadata (closing-fence line,
    /// first body line, optional rendered HTML). Mutates `text` to the body
    /// (front matter and leading blank lines stripped), matching the shape
    /// cmark expects. Returns `nil` — leaving `text` unchanged — when no
    /// front-matter delimiters are present.
    static func extractFrontMatterWithMeta(_ text: inout String) -> FrontMatterMeta? {
        guard text.hasPrefix("---") else { return nil }
        let startIndex = text.index(text.startIndex, offsetBy: 3)
        guard let endRange = text.range(of: "\n---", range: startIndex ..< text.endIndex) else {
            return nil
        }

        // closeLine = number of newlines up to and including the one before
        // the closing "---", +1 for 1-based numbering.
        let closeLine = text[..<endRange.upperBound].filter { $0 == "\n" }.count + 1

        let yaml = String(text[startIndex ..< endRange.lowerBound]).trimmingCharacters(in: .newlines)
        let rawAfter = String(text[endRange.upperBound...])
        let leadingNewlines = rawAfter.prefix(while: { $0 == "\n" }).count
        let firstBodyLine = closeLine + leadingNewlines

        text = rawAfter.trimmingCharacters(in: .newlines)

        // Parse simple "key: value" lines into an HTML table
        let rows = yaml.components(separatedBy: "\n").compactMap { line -> String? in
            guard let colonIndex = line.firstIndex(of: ":") else { return nil }
            let key = line[line.startIndex ..< colonIndex].trimmingCharacters(in: .whitespaces).htmlEscaped
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces).htmlEscaped
            return "<tr><td><strong>\(key)</strong></td><td>\(value)</td></tr>"
        }
        let html = rows.isEmpty
            ? nil
            : "<table data-sourcepos=\"1:1-\(closeLine):3\">\(rows.joined())</table>\n"
        return FrontMatterMeta(html: html, closeLine: closeLine, firstBodyLine: firstBodyLine)
    }

    /// Shifts every `data-sourcepos="A:x-B:y"` line number in `html` by
    /// `offset`. Used to translate cmark's body-relative line numbers into
    /// original-markdown line numbers when front matter was stripped.
    static func offsetSourcepos(in html: String, by offset: Int) -> String {
        html.replacing(sourceposRegex) { match in
            let s1 = (Int(match.output.1) ?? 0) + offset
            let c1 = match.output.2
            let s2 = (Int(match.output.3) ?? 0) + offset
            let c2 = match.output.4
            return "data-sourcepos=\"\(s1):\(c1)-\(s2):\(c2)\""
        }
    }

    private nonisolated(unsafe) static let sourceposRegex =
        /data-sourcepos="(\d+):(\d+)-(\d+):(\d+)"/

    /// Replaces `:shortcode:` emoji patterns with their Unicode equivalents.
    /// Uses single regex scan + dictionary lookup instead of iterating all entries.
    static func replaceEmojiShortcodes(_ text: String) -> String {
        guard text.contains(":") else { return text }
        return text.replacing(emojiRegex) { match in
            let key = String(match.output.1)
            return emojiMap[key] ?? String(match.output.0)
        }
    }

    private nonisolated(unsafe) static let emojiRegex = /:([a-z0-9_+]+):/

    // MARK: - cmark-gfm

    private static func cmarkToHTML(_ text: String, hardBreaks: Bool, mathRender: MathRenderClosure? = nil) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        var options: Int32 = CMARK_OPT_FOOTNOTES | CMARK_OPT_UNSAFE | CMARK_OPT_SOURCEPOS
        if hardBreaks { options |= CMARK_OPT_HARDBREAKS }

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in ["table", "autolink", "strikethrough", "tasklist", "tagfilter"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, text, text.utf8.count)
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        if let mathRender {
            MathExtractor.extract(in: doc, render: mathRender)
        }

        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let cString = cmark_render_html(doc, options, extensions) else { return "" }
        defer { free(cString) }

        return String(cString: cString)
    }

    // MARK: - Emoji Map (GitHub-compatible subset)

    private static let emojiMap: [String: String] = [
        // Smileys
        "smile": "😄", "laughing": "😆", "grinning": "😀", "grin": "😁",
        "joy": "😂", "smiley": "😃", "wink": "😉", "blush": "😊",
        "relaxed": "☺️", "yum": "😋", "heart_eyes": "😍", "kissing_heart": "😘",
        "thinking": "🤔", "neutral_face": "😐", "expressionless": "😑",
        "unamused": "😒", "sweat": "😓", "pensive": "😔", "confused": "😕",
        "disappointed": "😞", "worried": "😟", "angry": "😠", "rage": "😡",
        "cry": "😢", "sob": "😭", "scream": "😱", "sunglasses": "😎",
        "sleeping": "😴", "mask": "😷", "smirk": "😏", "stuck_out_tongue": "😛",
        "stuck_out_tongue_winking_eye": "😜", "flushed": "😳",
        // Gestures
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎",
        "ok_hand": "👌", "wave": "👋", "clap": "👏", "raised_hands": "🙌",
        "pray": "🙏", "muscle": "💪", "point_up": "☝️", "point_down": "👇",
        "point_left": "👈", "point_right": "👉",
        // People
        "person_frowning": "🙍", "person_with_pouting_face": "🙎",
        "raising_hand": "🙋", "bow": "🙇",
        // Hearts
        "heart": "❤️", "broken_heart": "💔", "sparkling_heart": "💖",
        "heartbeat": "💓", "heartpulse": "💗", "two_hearts": "💕",
        "revolving_hearts": "💞", "cupid": "💘", "love_letter": "💌",
        // Symbols
        "star": "⭐", "star2": "🌟", "sparkles": "✨", "zap": "⚡",
        "fire": "🔥", "boom": "💥", "collision": "💥", "sweat_drops": "💦",
        "droplet": "💧", "dash": "💨", "cloud": "☁️", "sun_with_face": "🌞",
        "rainbow": "🌈", "snowflake": "❄️",
        // Objects
        "rocket": "🚀", "airplane": "✈️", "car": "🚗", "taxi": "🚕",
        "bus": "🚌", "bike": "🚲", "ship": "🚢", "anchor": "⚓",
        "bell": "🔔", "key": "🔑", "lock": "🔒", "unlock": "🔓",
        "bulb": "💡", "wrench": "🔧", "hammer": "🔨", "nut_and_bolt": "🔩",
        "mag": "🔍", "mag_right": "🔎", "gem": "💎", "trophy": "🏆",
        "medal_sports": "🏅", "moneybag": "💰", "dollar": "💵",
        "pencil": "📝", "pencil2": "✏️", "memo": "📝",
        "book": "📖", "books": "📚", "bookmark": "🔖",
        "computer": "💻", "iphone": "📱", "email": "📧", "mailbox": "📫",
        "package": "📦", "gift": "🎁", "tada": "🎉", "balloon": "🎈",
        "camera": "📷", "video_camera": "📹", "movie_camera": "🎥",
        "headphones": "🎧", "art": "🎨", "microphone": "🎤",
        // Nature
        "dog": "🐶", "cat": "🐱", "mouse": "🐭", "rabbit": "🐰",
        "bear": "🐻", "penguin": "🐧", "bird": "🐦", "turtle": "🐢",
        "bug": "🐛", "bee": "🐝", "ant": "🐜", "snail": "🐌",
        "snake": "🐍", "octopus": "🐙", "fish": "🐟", "whale": "🐳",
        "dolphin": "🐬", "horse": "🐴", "pig": "🐷", "monkey_face": "🐵",
        "cherry_blossom": "🌸", "rose": "🌹", "sunflower": "🌻",
        "seedling": "🌱", "evergreen_tree": "🌲", "palm_tree": "🌴",
        "cactus": "🌵", "four_leaf_clover": "🍀", "mushroom": "🍄",
        // Food
        "apple": "🍎", "green_apple": "🍏", "grapes": "🍇", "watermelon": "🍉",
        "strawberry": "🍓", "peach": "🍑", "banana": "🍌", "lemon": "🍋",
        "pizza": "🍕", "hamburger": "🍔", "fries": "🍟", "coffee": "☕",
        "tea": "🍵", "beer": "🍺", "wine_glass": "🍷", "cake": "🎂",
        "cookie": "🍪", "chocolate_bar": "🍫", "ice_cream": "🍨",
        // Status
        "white_check_mark": "✅", "check": "✔️",
        "x": "❌", "negative_squared_cross_mark": "❎",
        "warning": "⚠️", "no_entry": "⛔", "no_entry_sign": "🚫",
        "sos": "🆘", "exclamation": "❗", "question": "❓",
        "100": "💯", "heavy_plus_sign": "➕", "heavy_minus_sign": "➖",
        "heavy_check_mark": "✔️", "bangbang": "‼️",
        // Arrows
        "arrow_up": "⬆️", "arrow_down": "⬇️", "arrow_left": "⬅️",
        "arrow_right": "➡️", "arrow_upper_right": "↗️",
        "arrows_counterclockwise": "🔄", "rewind": "⏪", "fast_forward": "⏩",
        // Misc
        "eyes": "👀", "tongue": "👅", "lips": "👄",
        "thought_balloon": "💭", "speech_balloon": "💬",
        "clock1": "🕐", "hourglass": "⌛",
        "hash": "#️⃣", "information_source": "ℹ️",
        "abc": "🔤", "abcd": "🔡", "1234": "🔢",
        "copyright": "©️", "registered": "®️", "tm": "™️",
    ]
}
