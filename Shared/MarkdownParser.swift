import Foundation
import CMarkGFM

/// Converts Markdown text to HTML using GitHub's cmark-gfm parser.
///
/// Supports GFM extensions: tables, task lists, strikethrough, autolinks, tagfilter.
/// Pre-processes: YAML front matter stripping, emoji shortcode replacement.
/// Runs natively in Swift (no JavaScript) for fast, authoritative GFM rendering.
enum MarkdownParser {

    /// Parse Markdown to HTML with all GFM extensions enabled.
    ///
    /// - Parameters:
    ///   - markdown: Raw Markdown text.
    ///   - unsafe: If `true`, allows raw HTML in Markdown (e.g., `<div>`).
    ///             Dangerous tags are still filtered by GFM tagfilter.
    ///             If `false`, all raw HTML is stripped. Default is `false`.
    /// - Returns: Rendered HTML string.
    static func toHTML(_ markdown: String, unsafe: Bool = false) -> String {
        var text = markdown
        text = stripFrontMatter(text)
        text = replaceMathCodeBlocks(text)
        text = replaceEmojiShortcodes(text)
        return cmarkToHTML(text, unsafe: unsafe)
    }

    // MARK: - Pre-processing

    /// Strips YAML front matter delimited by `---` at the start of the document.
    static func stripFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        // Find the closing --- (must be on its own line after the opening ---)
        let startIndex = text.index(text.startIndex, offsetBy: 3)
        guard let endRange = text.range(of: "\n---", range: startIndex..<text.endIndex) else {
            return text
        }
        return String(text[endRange.upperBound...]).trimmingCharacters(in: .newlines)
    }

    /// Converts ` ```math ` code blocks to `$$...$$` so KaTeX can render them.
    static func replaceMathCodeBlocks(_ text: String) -> String {
        guard text.contains("```math") else { return text }
        return text.replacing(mathCodeBlockRegex) { match in
            "$$\n\(match.output.1)\n$$"
        }
    }

    nonisolated(unsafe) private static let mathCodeBlockRegex = /```math\n([\s\S]*?)```/

    /// Replaces `:shortcode:` emoji patterns with their Unicode equivalents.
    /// Uses single regex scan + dictionary lookup instead of iterating all entries.
    static func replaceEmojiShortcodes(_ text: String) -> String {
        guard text.contains(":") else { return text }
        return text.replacing(emojiRegex) { match in
            let key = String(match.output.1)
            return emojiMap[key] ?? String(match.output.0)
        }
    }

    nonisolated(unsafe) private static let emojiRegex = /:([a-z0-9_+]+):/

    // MARK: - cmark-gfm

    private static func cmarkToHTML(_ text: String, unsafe: Bool) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        var options: Int32 = CMARK_OPT_FOOTNOTES
        if unsafe { options |= CMARK_OPT_UNSAFE }

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
