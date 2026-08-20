import Foundation

/// Splits filenames into meaningful lowercase words. Shared by the classifier
/// (keyword matching) and the project grouper (similarity), so both agree on
/// what counts as a "word" in a filename.
enum FilenameTokenizer {

    /// Words too common in filenames to imply two files are related.
    private static let stopwords: Set<String> = [
        "final", "draft", "copy", "new", "old", "latest", "version", "rev", "revised",
        "updated", "edit", "edited", "temp", "test", "untitled", "document", "file",
        "the", "and", "for", "with", "from", "sample", "backup", "export", "download",
        "screenshot", "screen", "shot", "img", "image", "photo", "pic", "scan", "doc"
    ]

    /// Lowercased words from a filename, excluding the extension, pure numbers,
    /// very short fragments, and stopwords.
    static func tokens(in filename: String) -> [String] {
        let base = (filename as NSString).deletingPathExtension
        let separated = base
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .lowercased()

        return separated
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { token in
                token.count >= 3
                    && !stopwords.contains(token)
                    && !token.allSatisfy(\.isNumber)
            }
    }

    /// Turns a token into a human-facing name, e.g. "thesis" -> "Thesis".
    static func displayName(for token: String) -> String {
        token.prefix(1).uppercased() + token.dropFirst()
    }
}
