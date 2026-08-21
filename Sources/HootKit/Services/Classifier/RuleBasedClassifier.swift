import Foundation

/// Classifies a file from its name and extension alone — no file contents are
/// read and nothing leaves the machine. This is the always-available fallback
/// that runs when no AI provider is configured, and the safety net for when
/// one is configured but unreachable.
public struct RuleBasedClassifier: FileClassifier {
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

    public func classify(_ file: FileItem) async throws -> ClassificationResult {
        classify(file, excerpt: nil)
    }

    /// Classifies with the file's own text when it's available.
    ///
    /// Text read from inside the file is an *independent* signal: a filename
    /// saying "invoice" and the document itself saying "invoice" are two
    /// separate chances to be right, and confidence reflects that.
    public func classify(_ file: FileItem, excerpt: String?) -> ClassificationResult {
        let tokens = Set(FilenameTokenizer.tokens(in: file.filename))
        let contentTokens: Set<String> = excerpt.map {
            Set(FilenameTokenizer.tokens(in: $0))
        } ?? []

        // Strongest signal: an explicit keyword match in the filename.
        var bestMatch: (rule: Rule, nameHits: [String], contentHits: [String])?
        for rule in Self.rules {
            let nameHits = rule.keywords.filter { tokens.contains($0) }
            let contentHits = rule.keywords.filter { contentTokens.contains($0) }
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
