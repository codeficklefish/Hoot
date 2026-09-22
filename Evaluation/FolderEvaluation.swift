import Foundation
import HootKit
import HootPlatformMac

/// Does a file end up in the folder the user would have put it in?
///
/// Runs the sources in the order the app runs them: filename rules, then the
/// personal model, then — only for what the personal model did not settle —
/// the provider. That order is the point. The personal model outranks
/// everything inferred, so a file it recognizes never reaches the language
/// model at all, and an evaluation that asked them in a different order would
/// be measuring an app nobody ships.
///
/// Reports accuracy and, more usefully, whether Hoot's stated confidence
/// matches how often it is actually right. A classifier that is 60% accurate
/// and says so is worth more than one that is 70% accurate and claims 95%,
/// because only the first can be left to decide on its own.
func evaluateFolders(_ corpus: [LabelledFile]) async {
    print("\n=== where files would go ===")

    let rules = RuleBasedClassifier()
    let extractor = MacPlatform.makeTextExtractor()
    let userFolders = EvaluationCorpus.folders(in: corpus)

    // Rules with the file's own text, as the app runs them.
    var base: [UUID: ClassificationResult] = [:]
    var readContent: Set<UUID> = []
    for entry in corpus {
        let excerpt = extractor.excerpt(for: entry.file)
        if excerpt != nil { readContent.insert(entry.file.id) }
        base[entry.file.id] = rules.classify(entry.file, excerpt: excerpt)
    }

    // The personal model, which outranks everything below it.
    let personal = PersonalModel(corpus)
    personal.reportUsability()

    var effective = base
    var settledByModel: Set<UUID> = []
    for (index, entry) in corpus.enumerated() {
        guard let prediction = personal.prediction(forFileAt: index),
              let folder = SuggestionValidator.sanitizeUserFolderName(prediction.folder)
        else { continue }

        effective[entry.file.id] = ClassificationResult(
            fileID: entry.file.id,
            category: folder,
            project: nil,
            suggestedFolder: folder,
            suggestedName: base[entry.file.id]?.suggestedName ?? entry.file.filename,
            confidence: ConfidenceModel.combine(
                [.matchesUserHistory(strength: prediction.strength)]),
            reason: "You usually file files like this under “\(folder)”."
        )
        settledByModel.insert(entry.file.id)
    }

    // Only what the personal model left open is worth a model round trip —
    // the same economy the app makes.
    let unsettled = corpus.filter { !settledByModel.contains($0.file.id) }.map(\.file)
    var refined: [UUID: ClassificationResult] = [:]
    if let provider = MacPlatform.makeAIProvider(for: .default), !unsettled.isEmpty {
        let refinement = await CategoryRefiner(
            provider: provider,
            extractor: MacPlatform.makeTextExtractor(),
            allowContentReading: true
        ).refine(unsettled, existing: effective, preferredFolders: userFolders)
        refined = refinement.results

        // The measurement this harness exists for is worthless if the model
        // never answered, and a lower number is exactly what that looks like.
        if let failure = refinement.failure {
            print("\n!! the model failed and every file fell back to rules: \(failure)\n")
        }
    }

    report(corpus, base: base, effective: effective, refined: refined,
           settledByModel: settledByModel, readContent: readContent)
}

// MARK: - The personal model, without marking its own homework

/// `LearnedClassifier` as the app would hold it, minus the file being judged.
///
/// Training on every file and then predicting one of them would be marking
/// its own homework: the folder a file sits in is both the label it was
/// trained on and the answer it is scored against, so the model would look
/// close to perfect while saying nothing at all. Leave-one-out is the honest
/// version, and the same thing `LearnedClassifier.crossValidate` does for the
/// number Settings shows the user.
private struct PersonalModel {
    private let samples: [LearnedClassifier.Sample]

    init(_ corpus: [LabelledFile]) {
        samples = corpus.map {
            LearnedClassifier.Sample(
                features: TrainingCorpus.features(for: $0.file),
                folder: $0.trueFolder
            )
        }
    }

    /// What the model says about one file, having never been shown it.
    func prediction(forFileAt index: Int) -> LearnedClassifier.Prediction? {
        var rest = samples
        let held = rest.remove(at: index)
        let model = LearnedClassifier.train(on: rest)
        guard model.isUsable else { return nil }
        return model.predict(held.features)
    }

    /// Says whether the model can run at all, and when it cannot, why.
    ///
    /// Silence here is the common case for a folder someone has only just
    /// started sorting, and it looks exactly like the model being useless.
    /// Naming the two thresholds it is short of is the difference between
    /// "this does not work" and "this needs more filing first".
    func reportUsability() {
        let perFolder = Dictionary(grouping: samples, by: \.folder).mapValues(\.count)
        let qualifying = perFolder.filter { $0.value >= LearnedClassifier.minimumExamplesPerFolder }
        let usable = LearnedClassifier.train(on: samples).isUsable

        guard !usable else {
            let (accuracy, answered, total) = LearnedClassifier.crossValidate(samples)
            print("personal model: \(qualifying.count) folders with "
                + "\(LearnedClassifier.minimumExamplesPerFolder)+ examples; right "
                + "\(EvaluationCorpus.percent(accuracy)) of the "
                + "\(EvaluationCorpus.percent(Double(answered) / Double(total))) it recognizes")
            return
        }

        print("personal model: silent. It needs \(LearnedClassifier.minimumCorpusSize) examples "
            + "in folders holding \(LearnedClassifier.minimumExamplesPerFolder)+ each, and this "
            + "corpus has \(samples.count) across \(perFolder.count) folders, "
            + "\(qualifying.count) of which are big enough.")
        if let biggest = perFolder.values.max() {
            print("                The largest holds \(biggest). Nothing below is the model's fault.")
        }
    }
}

// MARK: - Reporting

private func report(
    _ corpus: [LabelledFile],
    base: [UUID: ClassificationResult],
    effective: [UUID: ClassificationResult],
    refined: [UUID: ClassificationResult],
    settledByModel: Set<UUID>,
    readContent: Set<UUID>
) {
    print("\nfile                               | you        | rules      | final      | conf | from")
    print(String(repeating: "-", count: 104))

    var correct = 0, rulesCorrect = 0, modelCorrect = 0
    var claimedConfidence = 0.0

    for entry in corpus.sorted(by: { $0.trueFolder < $1.trueFolder }) {
        guard let ruled = base[entry.file.id] else { continue }
        let final = refined[entry.file.id] ?? effective[entry.file.id] ?? ruled

        let hit = final.suggestedFolder.lowercased() == entry.trueFolder.lowercased()
        if hit { correct += 1 }
        if ruled.suggestedFolder.lowercased() == entry.trueFolder.lowercased() { rulesCorrect += 1 }
        if settledByModel.contains(entry.file.id), hit { modelCorrect += 1 }
        claimedConfidence += final.confidence

        let source: String
        if refined[entry.file.id] != nil { source = "AI" }
        else if settledByModel.contains(entry.file.id) { source = "history" }
        else { source = "rules" }

        print(EvaluationCorpus.column(entry.file.filename, 34) + " | "
            + EvaluationCorpus.column(entry.trueFolder, 10) + " | "
            + EvaluationCorpus.column(ruled.suggestedFolder, 10) + " | "
            + EvaluationCorpus.column(final.suggestedFolder, 10) + " | "
            + EvaluationCorpus.column("\(Int(final.confidence * 100))%", 4) + " | "
            + (hit ? "OK   " : "MISS ") + EvaluationCorpus.column(source, 8)
            + (readContent.contains(entry.file.id) ? "content" : "name only"))
    }

    let total = Double(corpus.count)
    let accuracy = Double(correct) / total
    let claimed = claimedConfidence / total

    print("\nrules alone:   \(rulesCorrect)/\(corpus.count) = "
        + "\(EvaluationCorpus.percent(Double(rulesCorrect) / total))")
    if !settledByModel.isEmpty {
        print("your filing:   answered \(settledByModel.count), right \(modelCorrect) "
            + "(\(EvaluationCorpus.percent(Double(modelCorrect) / Double(settledByModel.count))))")
    }
    print("all together:  \(correct)/\(corpus.count) = \(EvaluationCorpus.percent(accuracy))")
    print("mean claimed confidence: \(EvaluationCorpus.percent(claimed))")
    print("=> overconfidence gap: \(Int(((claimed - accuracy) * 100).rounded())) points")
}
