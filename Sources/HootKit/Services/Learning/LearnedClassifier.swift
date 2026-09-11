import Foundation

/// Learns where *this* user files things, from folders they sorted themselves.
///
/// The general model can't know that a particular person keeps software books
/// apart from other books, or files anything mentioning a certain client under
/// one project. That knowledge is in their existing folders, and it is
/// learnable from a few hundred examples without any model training: a
/// multinomial naive-Bayes classifier over filename words is enough, runs in
/// milliseconds, never leaves the machine, and gives the same answer twice.
///
/// It is deliberately cautious. Personal archives have very uneven category
/// sizes, and a classifier trained on a handful of examples will happily
/// invent patterns, so folders with too few examples are ignored, the model
/// refuses to run below a minimum corpus size, and it only speaks up when one
/// folder is a decisive winner.
public struct LearnedClassifier: Codable {
    public init() {}


    /// A folder needs at least this many examples before it can be predicted.
    /// Below this, "patterns" are usually coincidence.
    public static let minimumExamplesPerFolder = 5
    /// The model stays silent entirely until the corpus reaches this size.
    public static let minimumCorpusSize = 30
    /// How much more likely the winner must be than the runner-up, in log
    /// space, before the answer is treated as decisive.
    public static let decisiveMargin = 1.5

    public struct Prediction {
        public let folder: String
        /// 0...1, derived from how far ahead the winner is — not from the
        /// raw posterior, which is wildly overconfident for text models.
        /// Becomes the weight of `ConfidenceModel.Signal.matchesUserHistory`.
        public let strength: Double
    }

    /// One training example: the words describing a file, and where the user
    /// actually put it.
    public struct Sample {
        public init(features: [String], folder: String) {
            self.features = features
            self.folder = folder
        }

        public let features: [String]
        public let folder: String
    }

    private var folderCounts: [String: Int] = [:]
    private var tokenCounts: [String: [String: Int]] = [:]   // folder -> token -> n
    private var tokensPerFolder: [String: Int] = [:]
    private var vocabulary: Set<String> = []
    public private(set) var totalSamples = 0

    public var isUsable: Bool {
        totalSamples >= Self.minimumCorpusSize && folderCounts.count >= 2
    }

    public var learnedFolders: [(folder: String, examples: Int)] {
        folderCounts.sorted { $0.value > $1.value }.map { (folder: $0.key, examples: $0.value) }
    }

    // MARK: - Training

    public static func train(on samples: [Sample]) -> LearnedClassifier {
        var model = LearnedClassifier()

        // Drop folders with too few examples rather than pretending to know them.
        var perFolder: [String: [Sample]] = [:]
        for sample in samples { perFolder[sample.folder, default: []].append(sample) }
        let usable = perFolder.filter { $0.value.count >= minimumExamplesPerFolder }

        for (folder, folderSamples) in usable {
            model.folderCounts[folder] = folderSamples.count
            model.totalSamples += folderSamples.count

            var counts: [String: Int] = [:]
            var total = 0
            for sample in folderSamples {
                // Count each word once per file: a word repeated in one
                // filename says no more than a word appearing once.
                for token in Set(sample.features) {
                    counts[token, default: 0] += 1
                    total += 1
                    model.vocabulary.insert(token)
                }
            }
            model.tokenCounts[folder] = counts
            model.tokensPerFolder[folder] = total
        }

        return model
    }

    // MARK: - Prediction

    public func predict(_ features: [String]) -> Prediction? {
        guard isUsable else { return nil }

        let unique = Set(features).filter { vocabulary.contains($0) }
        // Nothing recognizable means no opinion, rather than a guess drawn
        // purely from which folder happens to be biggest.
        guard !unique.isEmpty else { return nil }

        let vocabularySize = Double(vocabulary.count)
        var scores: [(folder: String, score: Double)] = []

        for (folder, count) in folderCounts {
            let prior = log(Double(count) / Double(totalSamples))
            let denominator = Double(tokensPerFolder[folder] ?? 0) + vocabularySize
            var score = prior
            for token in unique {
                let occurrences = Double(tokenCounts[folder]?[token] ?? 0)
                // Laplace smoothing: an unseen word makes a folder unlikely,
                // never impossible.
                score += log((occurrences + 1) / denominator)
            }
            scores.append((folder, score))
        }

        scores.sort { $0.score > $1.score }
        guard let best = scores.first else { return nil }

        let margin = scores.count > 1 ? best.score - scores[1].score : Self.decisiveMargin
        guard margin >= Self.decisiveMargin else { return nil }

        // Map the margin onto a bounded strength. A runaway winner doesn't
        // justify claiming certainty.
        //
        // The floor sits above `ClassificationResult.lowConfidenceThreshold`
        // rather than on it: this number becomes a confidence directly, and a
        // prediction balanced exactly on the line between "file it" and "leave
        // it alone" would be decided by floating-point luck.
        let strength = min(0.55 + (margin - Self.decisiveMargin) / 12, 0.85)

        return Prediction(folder: best.folder, strength: strength)
    }

    // MARK: - Persistence

    private static func storeURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        let folder = base.appending(path: "Hoot", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return folder.appending(path: "learned.json")
    }

    public static func load(from url: URL? = nil) -> LearnedClassifier? {
        let target = url ?? storeURL()
        guard let data = try? Data(contentsOf: target) else { return nil }
        return try? JSONDecoder().decode(LearnedClassifier.self, from: data)
    }

    public func save(to url: URL? = nil) {
        let target = url ?? Self.storeURL()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: target, options: .atomic)
        // The model encodes the user's filenames; keep it to the owner.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    // MARK: - Honest self-assessment

    /// Leave-one-out accuracy: train on every example but one, predict that
    /// one, repeat. Reports how often the model is right on files it has not
    /// seen, which is the only number worth showing a user.
    public static func crossValidate(_ samples: [Sample]) -> (accuracy: Double, answered: Int, total: Int) {
        guard samples.count >= minimumCorpusSize else { return (0, 0, samples.count) }

        var correct = 0
        var answered = 0
        for index in samples.indices {
            var rest = samples
            let held = rest.remove(at: index)
            let model = train(on: rest)
            guard let prediction = model.predict(held.features) else { continue }
            answered += 1
            if prediction.folder == held.folder { correct += 1 }
        }
        return (answered == 0 ? 0 : Double(correct) / Double(answered), answered, samples.count)
    }
}
