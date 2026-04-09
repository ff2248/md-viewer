import SwiftUI
import UniformTypeIdentifiers

/// A read-only Markdown document for DocumentGroup.
/// Each window gets its own MarkdownDocument instance.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdown, .plainText]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    /// Read-only viewer — write returns the original text unchanged
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
