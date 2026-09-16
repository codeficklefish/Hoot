import Foundation

/// A name Hoot is prepared to propose for a file, and why.
public struct ProposedName: Hashable {
    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }

    /// A complete filename, including the extension the file already had.
    public let name: String
    /// One sentence the user can judge the rename by, shown in review.
    public let reason: String
}

/// Proposes names for the files whose own names say nothing.
///
/// This is the last of the four ways a filename can fail Hoot. The first
/// three — a name that hints at the wrong folder, at no folder, at a folder
/// the user doesn't keep — are answered by putting the file somewhere better.
/// A file called `3721984.pdf` is answered by that and still lost, because
/// the folder is the only thing that improved.
///
/// Two rules keep this from becoming invention:
///
/// 1. **Only meaningless names are touched.** See `MeaninglessName`. A name
///    someone chose is never replaced, however much better a model's reads.
/// 2. **Only text actually read out of the file counts.** Not the name, not
///    the folder it was grouped into, and not a guess about what a picture
///    shows — words that are genuinely in the file. A name is a claim about
///    what something *is*, and a scene label ("appears to show: outdoor,
///    sky") cannot support one.
///
/// What survives both is still only a proposal: it reaches the user as a
/// suggested move like any other, is refused by unticking it, and is undone
/// by undoing the batch, which puts the old name back with the file.
public struct FileRenamer {
    private let provider: AIProvider

    public init(provider: AIProvider) {
        self.provider = provider
    }

    /// Returns replacement names keyed by file id. Files absent from the
    /// result keep the name they arrived with, which is the common case.
    ///
    /// - Parameter evidence: what was read from inside each file, gathered
    ///   once by the caller. Passed in rather than re-read: OCR and PDF
    ///   parsing are the expensive part of an analysis, and a rename is not
    ///   worth paying for them twice.
    public func proposeNames(
        for files: [FileItem],
        evidence: [UUID: ExtractedEvidence]
    ) async -> [UUID: ProposedName] {

        // A name is derived from the file's contents, and contents are only
        // ever shown to a provider running on this machine. Checked before
        // anything is asked, so a remote provider is never even handed the
        // question.
        guard provider.isLocal else { return [:] }

        let candidates = files.filter { file in
            guard !file.isCloudPlaceholder else { return false }
            guard MeaninglessName.applies(to: file.filename) else { return false }
            guard let found = evidence[file.id] else { return false }
            return found.isTextual && !found.excerpt.isEmpty
        }
        guard !candidates.isEmpty else { return [:] }
        guard case .available = await provider.availability() else { return [:] }

        // Kept rather than rebuilt from `evidence` later: what the model was
        // shown is what its answer has to be justified by, and re-deriving it
        // is how the two quietly come apart.
        var excerpts: [UUID: String] = [:]
        let descriptors = candidates.map { file -> FileDescriptor in
            let excerpt = evidence[file.id]?.excerpt
            if let excerpt { excerpts[file.id] = excerpt }
            return FileDescriptor(
                id: file.id,
                filename: file.filename,
                sizeDescription: file.displaySize,
                modifiedAt: file.modifiedAt,
                excerpt: excerpt
            )
        }

        let suggestions: [NameSuggestion]
        do {
            suggestions = try await provider.suggestNames(for: descriptors)
        } catch {
            // A rename is an improvement, never a requirement: the plan is
            // complete without it, so a failure here leaves the original
            // names in place rather than holding anything up.
            NSLog("Hoot: naming failed (\(error.localizedDescription)); keeping original names.")
            return [:]
        }

        return match(suggestions, to: candidates, excerpts: excerpts)
    }

    /// Matches answers back to the files they were asked about.
    ///
    /// Two passes, and the order between them is the point. A suggestion that
    /// names its file outright is certain, and is settled first; only then may
    /// the numbers pick up what is left. Running them the other way round
    /// would let a number overrule a file the model named exactly — trading a
    /// certainty for a guess, which is the one trade never worth making.
    private func match(
        _ suggestions: [NameSuggestion],
        to candidates: [FileItem],
        excerpts: [UUID: String]
    ) -> [UUID: ProposedName] {

        var byName: [String: FileItem] = [:]
        for file in candidates { byName[file.filename] = file }

        var proposals: [UUID: ProposedName] = [:]
        var unmatched: [NameSuggestion] = []

        for suggestion in suggestions {
            guard let file = byName[suggestion.filename] else {
                unmatched.append(suggestion)
                continue
            }
            claim(file, with: suggestion, excerpt: excerpts[file.id], into: &proposals)
        }

        // The numbers exist because the filenames this feature is for are
        // exactly the ones that are hard to copy. Asked to echo `------.txt`
        // back, the model returned it one dash short and a perfectly good
        // name was thrown away.
        for suggestion in unmatched {
            guard let index = suggestion.requestIndex else { continue }
            // One-based, and only ever into the request that was actually
            // sent: a number past the end refers to nothing.
            guard index >= 1, index <= candidates.count else { continue }
            let file = candidates[index - 1]
            guard proposals[file.id] == nil else { continue }
            claim(file, with: suggestion, excerpt: excerpts[file.id], into: &proposals)
        }

        return proposals
    }

    /// Records a name for a file, if the name survives being checked and the
    /// file has not already been named. A file is named once: a second answer
    /// for it is a model contradicting itself, and the first was the one that
    /// came with the most certainty behind it.
    private func claim(
        _ file: FileItem,
        with suggestion: NameSuggestion,
        excerpt: String?,
        into proposals: inout [UUID: ProposedName]
    ) {
        guard proposals[file.id] == nil else { return }
        guard let name = SuggestionValidator.sanitizeFilename(
            suggestion.proposedName,
            keepingExtensionOf: file.filename,
            groundedIn: excerpt
        ) else { return }

        proposals[file.id] = ProposedName(
            name: name,
            reason: Self.sanitizeReason(suggestion.reason)
        )
    }

    /// The reason is shown to the user verbatim, so it is trimmed and capped
    /// but never trusted to be short.
    private static func sanitizeReason(_ raw: String) -> String {
        let cleaned = raw
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return "Named from the text inside the file." }
        return cleaned.count > 160 ? String(cleaned.prefix(160)) + "…" : cleaned
    }
}
