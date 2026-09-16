import Foundation

/// Classifies a file from its name and extension alone — no file contents are
/// read and nothing leaves the machine. This is the always-available fallback
/// that runs when no AI provider is configured, and the safety net for when
/// one is configured but unreachable.
public struct RuleBasedClassifier {
    public init() {}


    /// A category signalled by keywords appearing in a filename.
    private struct Rule {
        let category: String
        let keywords: [String]
        /// Subfolder used when this rule wins and the file lands in a project.
        let subfolder: String?
    }

    private static let rules: [Rule] = [
        Rule(category: "School",
             keywords: ["thesis", "dissertation", "chapter", "assignment", "homework",
                        "syllabus", "lecture", "exam", "midterm", "finals", "coursework"],
             subfolder: "Documents"),
        Rule(category: "Research",
             keywords: ["research", "study", "paper", "journal", "article", "citation",
                        "bibliography", "abstract", "literature"],
             subfolder: "Research"),
        Rule(category: "Data",
             keywords: ["survey", "results", "dataset", "data", "responses", "sample",
                        "statistics", "stats", "analysis"],
             subfolder: "Data"),
        Rule(category: "Finance",
             keywords: ["invoice", "receipt", "billing", "payment", "statement", "tax",
                        "payroll", "quote", "estimate", "refund"],
             subfolder: "Finance"),
        Rule(category: "Work",
             keywords: ["contract", "agreement", "proposal", "report", "meeting", "minutes",
                        "resume", "cv", "offer", "onboarding", "client"],
             subfolder: "Documents"),
        Rule(category: "Books",
             keywords: ["ebook", "epub", "isbn", "edition", "oreilly", "reilly", "manning",
                        "packt", "apress", "wiley", "springer", "textbook", "handbook",
                        "cookbook", "novel"],
             subfolder: nil),
        Rule(category: "Legal",
             keywords: ["nda", "policy", "terms", "license", "permit", "affidavit"],
             subfolder: "Documents")
    ]

    /// Every rule's keywords paired with the stem a filename's own words are
    /// compared against.
    ///
    /// Built once beside the rules rather than per file: the rules never
    /// change, and stemming them again for every file would be the same
    /// answer recomputed thousands of times. Declaration order is kept, so
    /// the sentence explaining a classification still lists a rule's words in
    /// the order the rule does.
    private static let stemmedRules: [(rule: Rule, keywords: [(stem: String, word: String)])] =
        rules.map { rule in
            (rule, rule.keywords.map { (stem: WordStem.stem($0), word: $0) })
        }

    /// Classifies with the file's own text when it's available; pass `nil`
    /// for `excerpt` to classify on the filename alone.
    ///
    /// Text read from inside the file is an *independent* signal: a filename
    /// saying "invoice" and the document itself saying "invoice" are two
    /// separate chances to be right, and confidence reflects that.
    public func classify(_ file: FileItem, excerpt: String?) -> ClassificationResult {
        // Stemmed on both sides, so `Invoices-2024.pdf` reaches the rule that
        // lists "invoice". Comparing the words as written meant the plural of
        // nearly every keyword here missed outright — receipts, taxes,
        // contracts, statements, results — which are the commonest things in
        // a downloads folder, not edge cases.
        let tokens = Set(FilenameTokenizer.tokens(in: file.filename).map(WordStem.stem))
        let contentTokens: Set<String> = excerpt.map {
            Set(FilenameTokenizer.tokens(in: $0).map(WordStem.stem))
        } ?? []

        // Strongest signal: an explicit keyword match in the filename.
        var bestMatch: (rule: Rule, nameHits: [String], contentHits: [String])?
        for (rule, keywords) in Self.stemmedRules {
            let nameHits = keywords.filter { tokens.contains($0.stem) }.map(\.word)
            let contentHits = keywords.filter { contentTokens.contains($0.stem) }.map(\.word)
            let score = nameHits.count * 2 + contentHits.count
            let bestScore = (bestMatch?.nameHits.count ?? 0) * 2 + (bestMatch?.contentHits.count ?? 0)
            if score > 0, score > bestScore {
                bestMatch = (rule, nameHits, contentHits)
            }
        }

        if let match = bestMatch {
            var signals: [ConfidenceModel.Signal] = []
            signals.append(contentsOf: match.nameHits.map { _ in .filenameKeyword })
            signals.append(contentsOf: match.contentHits.map { _ in .contentKeyword })

            var reason: [String] = []
            if !match.nameHits.isEmpty {
                reason.append("filename mentions \(match.nameHits.map { "“\($0)”" }.joined(separator: ", "))")
            }
            if !match.contentHits.isEmpty {
                reason.append("its text mentions \(match.contentHits.map { "“\($0)”" }.joined(separator: ", "))")
            }

            return ClassificationResult(
                fileID: file.id,
                category: match.rule.category,
                project: nil,
                suggestedFolder: match.rule.category,
                suggestedName: file.filename,
                confidence: ConfidenceModel.combine(signals),
                reason: reason.joined(separator: "; ").prefix(1).uppercased()
                    + reason.joined(separator: "; ").dropFirst() + "."
            )
        }

        // No keyword matched, but the extension may still identify the file
        // beyond doubt. Confidence here answers "do we know what this is?",
        // not "do we know which project it belongs to" — a photo with a
        // meaningless camera-roll name is still certainly a photo, and
        // belongs in Images rather than being left behind.
        let category = Self.categoryForKind(file.kind)
        if file.kind.isRecognized {
            return ClassificationResult(
                fileID: file.id,
                category: category,
                project: nil,
                suggestedFolder: category,
                suggestedName: file.filename,
                confidence: ConfidenceModel.combine([.recognizedType]),
                reason: "Recognized as \(Self.describe(file.kind)) from its file type."
            )
        }

        // Genuinely unknown: an extension we don't recognize and no keywords.
        // This is the only case that stays below the threshold.
        return ClassificationResult(
            fileID: file.id,
            category: category,
            project: nil,
            suggestedFolder: category,
            suggestedName: file.filename,
            confidence: ConfidenceModel.combine([]),
            reason: "Unrecognized file type and no matching keywords."
        )
    }

    private static func describe(_ kind: FileItem.Kind) -> String {
        switch kind {
        case .document: return "a document"
        case .spreadsheet: return "a spreadsheet"
        case .image: return "an image"
        case .pdf: return "a PDF"
        case .text: return "a text file"
        case .book: return "an e-book"
        case .archive: return "an archive"
        case .installer: return "an app installer"
        case .media: return "a media file"
        case .other: return "an unknown file"
        }
    }

    /// The folder a file falls into on type alone. Exposed so callers can
    /// tell a claim about *what a file is* from a claim about *what it's
    /// about* — "Images" is the former, "Photography" the latter.
    public static func typeCategory(for file: FileItem) -> String {
        categoryForKind(file.kind)
    }

    /// Whether a folder name answers *what a file is* rather than what it is
    /// about.
    ///
    /// The distinction decides who is allowed to overrule whom. A file's type
    /// is settled by its extension and is not open to opinion, so a model
    /// offering one of these names in place of another is contradicting the
    /// filesystem rather than adding to it — `Landing page redesign.zip` was
    /// moved out of Archives and into Images on the strength of the PNGs
    /// listed inside it, which is a true statement about the contents and no
    /// statement at all about the file.
    ///
    /// Both vocabularies are listed because two of them exist: sorting by
    /// type produces `TypeSorter.allFolders`, while the rules here fall back
    /// to a shorter set of their own.
    public static func namesAFileType(_ folder: String) -> Bool {
        typeFolderNames.contains(folder.lowercased())
    }

    private static let typeFolderNames: Set<String> = Set(
        (TypeSorter.allFolders + ["Notes", "Media", "Unsorted"]).map { $0.lowercased() }
    )

    private static func categoryForKind(_ kind: FileItem.Kind) -> String {
        switch kind {
        case .image: return "Images"
        case .spreadsheet: return "Spreadsheets"
        case .pdf, .document: return "Documents"
        case .text: return "Notes"
        case .book: return "Books"
        case .archive: return "Archives"
        case .installer: return "Installers"
        case .media: return "Media"
        case .other: return "Unsorted"
        }
    }
}
