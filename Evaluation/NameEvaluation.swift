import Foundation
import HootKit
import HootPlatformMac

/// Which of the names you kept would Hoot offer to overwrite?
///
/// Every filename in a folder the user organized has survived their attention.
/// Some are genuinely meaningless — filed without renaming, and exactly what
/// this feature is for — but the rest are names they chose, and `MeaninglessName`
/// firing on one of those is the expensive mistake: a model's invention put
/// where a person's own words used to be.
///
/// The rate is printed, but the list matters more. Only the user can say which
/// lines are their own words, so this prints them all rather than claiming a
/// false-positive rate it is in no position to calculate.
func evaluateMeaninglessNames(_ corpus: [LabelledFile]) {
    print("\n=== names Hoot would offer to replace ===")

    let flagged = corpus
        .filter { MeaninglessName.applies(to: $0.file.filename) }
        .sorted { $0.file.filename.lowercased() < $1.file.filename.lowercased() }

    for entry in flagged {
        print("  \(entry.trueFolder)/\(entry.file.filename)")
    }

    let rate = corpus.isEmpty ? 0 : Double(flagged.count) / Double(corpus.count)
    print("\nflagged \(flagged.count) of \(corpus.count) names you have kept "
        + "(\(EvaluationCorpus.percent(rate)))")
    print("Every line above that is a name you chose is a false positive — the "
        + "error this rule exists to avoid, and the only one worth tuning for.")
}

/// One file with its real name hidden, so the name can be the answer key.
private struct NamingSubject {
    let id = UUID()
    /// The name the user gave it.
    let real: String
    /// What Hoot is shown instead: a name that says nothing, which is the
    /// only condition under which this feature ever runs.
    let hidden: String
    /// The text the model is shown, and the text its answer is checked against.
    let excerpt: String
    let sizeDescription: String
    let modifiedAt: Date?
}

/// Can Hoot recover a name you chose, from the file's text alone?
///
/// Self-supervised, so it needs no labelling and no judgement call: take a
/// file whose name says something, hide the name, hand over the text, and see
/// how much of the user's own wording comes back. It is not asking for an
/// exact match — two people naming the same file agree on the subject and
/// differ on everything else — it is asking whether the words a person
/// independently chose are the words Hoot finds.
///
/// It also measures what the grounding check costs. Refusing a name because
/// its words are not in the text is only worth doing if it refuses few good
/// names, and that trade is a number, not an opinion.
func evaluateProposedNames(_ corpus: [LabelledFile], limit: Int) async {
    print("\n=== recovering names you chose ===")

    guard let provider = MacPlatform.makeAIProvider(for: .default) else {
        print("No provider is configured, so there is nothing to measure.")
        return
    }
    guard case .available = await provider.availability() else {
        print("The on-device model is not available, so names cannot be measured.")
        return
    }

    let subjects = gatherSubjects(from: corpus, limit: limit)
    guard !subjects.isEmpty else {
        print("No file here has both a name you chose and readable text inside.")
        return
    }
    print("\(subjects.count) files, each shown its own text and an opaque name.\n")

    let suggestions: [NameSuggestion]
    do {
        suggestions = try await provider.suggestNames(for: subjects.map(descriptor))
    } catch {
        print("The provider failed: \(error.localizedDescription)")
        return
    }

    report(match(suggestions, to: subjects), of: subjects)
}

// MARK: - Building the request

private func gatherSubjects(from corpus: [LabelledFile], limit: Int) -> [NamingSubject] {
    let extractor = MacPlatform.makeTextExtractor()
    var subjects: [NamingSubject] = []

    for entry in corpus {
        guard subjects.count < limit else { break }
        // A name that already says nothing is no answer key.
        guard !MeaninglessName.applies(to: entry.file.filename) else { continue }
        guard let evidence = extractor.evidence(for: entry.file),
              evidence.isTextual, !evidence.excerpt.isEmpty else { continue }

        subjects.append(
            NamingSubject(
                real: entry.file.filename,
                hidden: hiddenName(for: entry.file, number: subjects.count + 1),
                excerpt: evidence.excerpt,
                sizeDescription: entry.file.displaySize,
                modifiedAt: entry.file.modifiedAt
            )
        )
    }
    return subjects
}

/// The user's name replaced by a row of digits — a name `MeaninglessName`
/// agrees says nothing, so the model is answering the question the app would
/// actually ask it.
private func hiddenName(for file: FileItem, number: Int) -> String {
    let stem = String(format: "%010d", number)
    return file.fileExtension.isEmpty ? stem : "\(stem).\(file.fileExtension)"
}

private func descriptor(for subject: NamingSubject) -> FileDescriptor {
    FileDescriptor(
        id: subject.id,
        filename: subject.hidden,
        sizeDescription: subject.sizeDescription,
        modifiedAt: subject.modifiedAt,
        excerpt: subject.excerpt
    )
}

// MARK: - Reading the answers

private struct Answer {
    let subject: NamingSubject
    /// What the app would accept with only the path and placeholder rules.
    let ungrounded: String?
    /// What it accepts once the name must also be carried by the text.
    let grounded: String?
}

/// Matches answers back to files the same way `FileRenamer` does — by the
/// filename first, then by the number — so this measures the path the app
/// actually takes rather than an idealised one.
private func match(_ suggestions: [NameSuggestion], to subjects: [NamingSubject]) -> [Answer] {
    var byHiddenName: [String: NamingSubject] = [:]
    for subject in subjects { byHiddenName[subject.hidden] = subject }

    var claimed: Set<UUID> = []
    var answers: [Answer] = []

    func record(_ subject: NamingSubject, _ suggestion: NameSuggestion) {
        guard claimed.insert(subject.id).inserted else { return }
        answers.append(
            Answer(
                subject: subject,
                ungrounded: SuggestionValidator.sanitizeFilename(
                    suggestion.proposedName, keepingExtensionOf: subject.hidden
                ),
                grounded: SuggestionValidator.sanitizeFilename(
                    suggestion.proposedName,
                    keepingExtensionOf: subject.hidden,
                    groundedIn: subject.excerpt
                )
            )
        )
    }

    var unmatched: [NameSuggestion] = []
    for suggestion in suggestions {
        if let subject = byHiddenName[suggestion.filename] {
            record(subject, suggestion)
        } else {
            unmatched.append(suggestion)
        }
    }
    for suggestion in unmatched {
        guard let index = suggestion.requestIndex,
              index >= 1, index <= subjects.count else { continue }
        record(subjects[index - 1], suggestion)
    }

    return answers
}

// MARK: - Scoring

/// How much of one name is present in the other, word for word.
///
/// Stemmed and lowercased, because "Invoices" and "invoice" are the same word
/// for this purpose, and a scorer that says otherwise is measuring spelling.
private func sharedWords(_ left: String, _ right: String) -> (shared: Int, left: Int, right: Int) {
    func words(_ name: String) -> Set<String> {
        Set(FilenameTokenizer.tokens(in: (name as NSString).deletingPathExtension)
            .map(WordStem.stem))
    }
    let leftWords = words(left), rightWords = words(right)
    return (leftWords.intersection(rightWords).count, leftWords.count, rightWords.count)
}

private func report(_ answers: [Answer], of subjects: [NamingSubject]) {
    print("your name                          | Hoot's proposal                    | shared")
    print(String(repeating: "-", count: 96))

    var recall = 0.0, precision = 0.0, named = 0, touchedOne = 0

    for answer in answers.sorted(by: { $0.subject.real < $1.subject.real }) {
        guard let proposal = answer.grounded else {
            let refused = answer.ungrounded == nil ? "declined" : "refused: not in the text"
            print(EvaluationCorpus.column(answer.subject.real, 34) + " | "
                + EvaluationCorpus.column(refused, 34) + " | —")
            continue
        }

        let overlap = sharedWords(proposal, answer.subject.real)
        named += 1
        if overlap.left > 0 { precision += Double(overlap.shared) / Double(overlap.left) }
        if overlap.right > 0 { recall += Double(overlap.shared) / Double(overlap.right) }
        if overlap.shared > 0 { touchedOne += 1 }

        print(EvaluationCorpus.column(answer.subject.real, 34) + " | "
            + EvaluationCorpus.column(proposal, 34) + " | "
            + "\(overlap.shared)/\(overlap.right)")
    }

    let total = Double(subjects.count)
    let wouldPropose = answers.filter { $0.ungrounded != nil }.count
    print("\nnamed: \(named)/\(subjects.count) "
        + "(\(EvaluationCorpus.percent(Double(named) / total)))")
    if named > 0 {
        print("mean word recall: "
            + "\(EvaluationCorpus.percent(recall / Double(named))) — how much of your name came back")
        print("mean word precision: "
            + "\(EvaluationCorpus.percent(precision / Double(named))) — how much of Hoot's name was in yours")
        print("shared at least one word: \(touchedOne)/\(named) "
            + "(\(EvaluationCorpus.percent(Double(touchedOne) / Double(named))))")
    }
    print("grounding refused \(wouldPropose - named) of the \(wouldPropose) names "
        + "that would otherwise have been proposed — the cost of insisting a "
        + "name be carried by the file's own text.")
}
