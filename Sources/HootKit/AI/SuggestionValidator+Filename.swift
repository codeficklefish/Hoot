import Foundation

/// The same defensive treatment as a folder name, applied to the other kind
/// of name a model can produce.
///
/// Kept beside `SuggestionValidator` rather than inside it only to hold both
/// files near the size the coding standards ask for; the rule is the one
/// stated there — model output is sanitized at the boundary, before it can
/// become a path on disk.
///
/// A filename is the riskier of the two. A bad folder name puts files in a
/// badly named folder; a bad filename replaces the one thing the user might
/// still have recognised the file by. So this is stricter than the folder
/// rules in three places: the extension is never the model's to choose, a
/// proposal that is itself meaningless is refused rather than cleaned up,
/// and anything that looks like a path is refused outright rather than
/// tidied into a name that happens to be safe.
extension SuggestionValidator {

    /// Reduces a model-proposed filename to something safe to move a file to,
    /// or nil when nothing usable survives.
    ///
    /// - Parameters:
    ///   - original: the file's current name. Its extension is kept exactly
    ///     as it is — renaming `boarding.pdf` to `Delta boarding pass` with
    ///     no extension, or with the wrong one, would break the way every
    ///     other program on the Mac opens it.
    ///   - excerpt: the text the model was shown for this file. Given, the
    ///     proposal must be carried by it — see `NameGrounding`. Omitted, the
    ///     path rules below still apply and only the invention check is
    ///     skipped, which is how the safety rules are exercised on their own.
    /// - Returns: a single path component carrying the original extension, or
    ///   nil if the proposal was empty, meaningless, unsafe, ungrounded, or
    ///   the name the file already has.
    ///
    /// `groundedIn` has no default. Passing nil is still allowed and still
    /// means "nothing to check the proposal against" — but it has to be
    /// written down. A safety rule with a default argument is a safety rule
    /// you can skip by forgetting, and forgetting is how the shelf's drag
    /// went two releases without asking rule 5.
    public static func sanitizeFilename(
        _ raw: String,
        keepingExtensionOf original: String,
        groundedIn excerpt: String?
    ) -> String? {
        // A proposal that reaches for a path is not a name that needs
        // cleaning; it is an answer to a question nobody asked. Cleaning
        // "../../Escape" leaves the perfectly good name "Escape", which is
        // how a traversal attempt turns into a silent success.
        guard !raw.contains("/"), !raw.contains("\\") else { return nil }
        guard !raw.contains("..") else { return nil }
        guard !raw.trimmingCharacters(in: .whitespaces).hasPrefix(".") else { return nil }

        let originalExtension = (original as NSString).pathExtension
        var name = strippingExtension(from: raw)

        // A colon cannot appear in a path component, but a model writing
        // "Receipt: March" is naming the file, not navigating anywhere — so
        // this one is stripped rather than refused.
        let forbidden = CharacterSet(charactersIn: ":\u{0}").union(.controlCharacters)
        name = name.components(separatedBy: forbidden).joined(separator: " ")
        name = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))

        guard !name.isEmpty else { return nil }
        guard !placeholders.contains(name.lowercased()) else { return nil }

        name = quietened(name)

        if name.count > maximumNameLength {
            name = String(name.prefix(maximumNameLength))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        }
        guard !name.isEmpty else { return nil }

        let candidate = originalExtension.isEmpty ? name : "\(name).\(originalExtension)"

        // The model is allowed to fail. Asked to name a file whose text says
        // nothing, it tends to answer with another placeholder or a version
        // of the name it was given — and swapping one meaningless name for
        // another is churn, not help.
        guard !MeaninglessName.applies(to: candidate) else { return nil }
        guard candidate.lowercased() != original.lowercased() else { return nil }

        // The last and least negotiable check. Everything above keeps a bad
        // name from being a dangerous *path*; this is what keeps it from
        // being a confident lie about the file.
        if let excerpt, !NameGrounding.isSupported(candidate, by: excerpt) { return nil }

        return candidate
    }

    /// Drops an extension the model appended of its own accord.
    ///
    /// Only a plainly alphabetic one: "Boarding pass.pdf" is a model adding an
    /// extension it was told not to, while the "03" in "Invoice 2024.03" is
    /// part of the name and keeping it matters.
    private static func strippingExtension(from raw: String) -> String {
        let proposed = (raw as NSString).pathExtension
        guard !proposed.isEmpty, proposed.count <= 5,
              proposed.allSatisfy(\.isLetter) else { return raw }
        return (raw as NSString).deletingPathExtension
    }

    /// Takes the shouting out of a name lifted from scanned paperwork.
    ///
    /// Forms and receipts are set in capitals, and the model copies that into
    /// the filename however firmly the prompt asks it not to — a folder of
    /// SHOUTING FILENAMES is not what anyone meant by a tidier folder. Only a
    /// proposal that is *entirely* upper case is touched: a name the model
    /// already cased deliberately, like "Trip to Cebu", is left exactly as it
    /// came.
    private static func quietened(_ name: String) -> String {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy(\.isUppercase) else { return name }

        var words: [String] = []
        for (offset, word) in name.split(separator: " ").map(String.init).enumerated() {
            // A reference number or an amount is not shouting; it is a value,
            // and its shape is part of what it says.
            if word.contains(where: \.isNumber) {
                words.append(word)
                continue
            }
            // An acronym has no vowel to lowercase. "PHP" stays "PHP" — the
            // known edge of the rule is that one carrying a vowel, like
            // "NDA", reads as a word and is cased like one.
            if !word.contains(where: { "AEIOU".contains($0) }) {
                words.append(word)
                continue
            }
            let lowered = word.lowercased()
            words.append(offset == 0 ? lowered.prefix(1).uppercased() + lowered.dropFirst() : lowered)
        }
        return words.joined(separator: " ")
    }
}
