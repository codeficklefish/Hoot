import Foundation

/// Upgrades the categories of files that belong to no project.
///
/// Rule-based classification can only see filenames, so a spreadsheet of tax
/// records lands in "Spreadsheets" — correct about the *type*, useless about
/// the *subject*. Given the text extracted from inside the file, a model can
/// place it in "Finance" instead.
///
/// Deterministic signals still win: a confident keyword match is left alone,
/// because a model's opinion shouldn't override evidence we can prove.
public struct CategoryRefiner {

    /// Above this, the rule-based classifier matched real keywords and is
    /// trusted over the model.
    private static let keywordEvidenceThreshold = 0.75

    /// Diagnostic trace of what the provider was asked and what came back,
    /// off unless HOOT_TRACE_REFINER is set. Refinement drops a suggestion
    /// whenever it cannot be matched back to a file, and silence about that
    /// is indistinguishable from the model having nothing to say.
    private static func trace(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["HOOT_TRACE_REFINER"] != nil else { return }
        FileHandle.standardError.write(Data("[refiner] \(message())\n".utf8))
    }

    /// The model reports 95-100% for everything, so its self-scored number is
    /// ignored entirely. Confidence comes from whether independent sources
    /// agree — see `ConfidenceModel`.

    public let provider: AIProvider
    public let allowContentReading: Bool

    private let extractor: TextExtracting

    public init(provider: AIProvider, extractor: TextExtracting, allowContentReading: Bool) {
        self.provider = provider
        self.extractor = extractor
        self.allowContentReading = allowContentReading
    }

    /// Returns replacement classifications, keyed by file id. Files absent
    /// from the result keep whatever the rule-based classifier decided.
    public func refine(
        _ files: [FileItem],
        existing: [UUID: ClassificationResult],
        preferredFolders: [String]
    ) async -> [UUID: ClassificationResult] {

        // Only bother with files whose category came from the file type alone.
        let candidates = files.filter { file in
            guard let current = existing[file.id] else { return false }
            return current.confidence < Self.keywordEvidenceThreshold
        }
        Self.trace("\(files.count) files, \(candidates.count) below the \(Self.keywordEvidenceThreshold) threshold")
        for file in candidates {
            Self.trace("  candidate: \(file.filename)")
        }
        guard !candidates.isEmpty else { return [:] }

        guard case .available = await provider.availability() else { return [:] }

        let mayReadContent = provider.isLocal && allowContentReading
        var excerpts: [UUID: String] = [:]
        let descriptors = candidates.map { file -> FileDescriptor in
            let excerpt = mayReadContent ? extractor.excerpt(for: file) : nil
            if let excerpt { excerpts[file.id] = excerpt }
            return FileDescriptor(
                id: file.id,
                filename: file.filename,
                sizeDescription: file.displaySize,
                modifiedAt: file.modifiedAt,
                excerpt: excerpt
            )
        }

        // Re-run the rules with the file's own text. This is what makes the
        // provider's answer checkable: two independent readings of the same
        // file either agree or they don't.
        let rules = RuleBasedClassifier()
        var contentInformed: [UUID: ClassificationResult] = [:]
        for file in candidates {
            contentInformed[file.id] = rules.classify(file, excerpt: excerpts[file.id])
        }

        let suggestions: [CategorySuggestion]
        do {
            suggestions = try await provider.suggestCategories(
                for: descriptors,
                preferredFolders: preferredFolders
            )
        } catch {
            NSLog("Hoot: category refinement failed (\(error.localizedDescription)); keeping rules.")
            Self.trace("provider threw: \(error.localizedDescription)")
            return [:]
        }

        Self.trace("provider returned \(suggestions.count) suggestions")
        for s in suggestions {
            Self.trace("  suggestion: filename=\(s.filename) category=\(s.category)")
        }

        // The model's output names folders on disk, so it goes through the
        // same sanitizing as project names.
        var byName: [String: FileItem] = [:]
        for file in candidates { byName[file.filename] = file }

        var refined: [UUID: ClassificationResult] = [:]
        for suggestion in suggestions {
            guard let file = byName[suggestion.filename] else {
                Self.trace("  DROPPED (no file named \(suggestion.filename))")
                continue
            }
            guard let folder = SuggestionValidator.sanitizeName(suggestion.category) else {
                Self.trace("  DROPPED (category \(suggestion.category) did not sanitize)")
                continue
            }
            guard let current = existing[file.id] else {
                Self.trace("  DROPPED (no existing result for \(suggestion.filename))")
                continue
            }

            let ruleView = contentInformed[file.id] ?? current
            let agrees = ruleView.suggestedFolder.lowercased() == folder.lowercased()

            // Where the rules already reached this answer from the file's own
            // text, the provider is corroboration and confidence rises. Where
            // they disagree, the provider's richer reading usually wins — but
            // the disagreement is recorded rather than hidden.
            var signals: [ConfidenceModel.Signal] = [.corroboratedByProvider]
            if excerpts[file.id] != nil { signals.append(.contentKeyword) }
            if agrees { signals.append(.filenameKeyword) }

            let confidence = ConfidenceModel.combine(signals, conflicting: !agrees)

            if agrees {
                // Same answer, better-grounded number: keep the rules' wording
                // and raise confidence rather than replacing the result.
                refined[file.id] = ClassificationResult(
                    fileID: file.id,
                    category: ruleView.category,
                    project: nil,
                    suggestedFolder: ruleView.suggestedFolder,
                    suggestedName: current.suggestedName,
                    confidence: confidence,
                    reason: "\(ruleView.reason) On-device analysis agreed."
                )
                continue
            }

            guard folder.lowercased() != current.suggestedFolder.lowercased() else { continue }

            // The provider disagreed. Its reading is usually richer, but a
            // disagreement is penalised, so it can end up less certain than
            // the answer it would replace.
            //
            // Only defend the existing answer when it actually says something
            // about the file's subject. "Images" asserts what a file *is*, and
            // however confidently, that is no answer to what it is *about* —
            // so a subject reading may replace it even at lower confidence.
            // A keyword-derived answer like "Finance" is a subject claim, and
            // must be beaten on evidence rather than merely contradicted.
            let existingIsTypeOnly = ruleView.suggestedFolder
                == RuleBasedClassifier.typeCategory(for: file)
            if !existingIsTypeOnly, confidence <= ruleView.confidence { continue }

            refined[file.id] = ClassificationResult(
                fileID: file.id,
                category: folder,
                project: nil,
                suggestedFolder: folder,
                suggestedName: current.suggestedName,
                confidence: confidence,
                reason: suggestion.reason
            )
        }
        return refined
    }
}
