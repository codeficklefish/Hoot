import Foundation

/// Works out how much to trust a classification, from evidence rather than
/// self-assessment.
///
/// Asking a language model how confident it is doesn't work: in testing the
/// on-device model reported 95–100% for every answer, including wrong ones.
/// A number that is always high carries no information, and it silently
/// disabled the "leave low-confidence files alone" safety rule.
///
/// Instead, confidence is built from independent signals and combined with a
/// noisy-OR rule: each signal is one more chance to be right, so agreement
/// between unrelated sources raises confidence faster than any single source
/// can on its own. Two signals that could each fail independently — a word in
/// the filename *and* the same subject in the file's text — are much stronger
/// evidence than one signal repeated.
public enum ConfidenceModel {

    /// A piece of evidence, with the weight it carries alone.
    public enum Signal {
        /// A category keyword appears in the filename.
        case filenameKeyword
        /// A category keyword appears in text read from inside the file.
        case contentKeyword
        /// The extension identifies the file's type beyond doubt.
        case recognizedType
        /// A provider independently reached the same category as the rules.
        case corroboratedByProvider
        /// The file shares distinctive vocabulary with others in its project.
        case sharedProjectVocabulary
        /// It resembles files the user has already filed in a folder of
        /// theirs, by the margin the personal model measured.
        ///
        /// The only signal that carries its own weight. That is not the
        /// self-assessment this module exists to refuse — it is the distance
        /// between the winning folder and the runner-up, measured from the
        /// user's own filing, and a bare-margin winner genuinely is worth less
        /// than a runaway one.
        case matchesUserHistory(strength: Double)

        var weight: Double {
            switch self {
            case .filenameKeyword: return 0.62
            case .contentKeyword: return 0.58
            // Enough to file by type, but it says nothing about the subject.
            case .recognizedType: return 0.55
            case .corroboratedByProvider: return 0.60
            case .sharedProjectVocabulary: return 0.50
            // The strongest signal available: not a guess about what the
            // file is, but evidence of what this person actually does. Its
            // weight is the margin the model measured rather than a constant,
            // so a close call is not sold as a certainty.
            case .matchesUserHistory(let strength): return strength
            }
        }

        var description: String {
            switch self {
            case .filenameKeyword: return "the filename"
            case .contentKeyword: return "text inside the file"
            case .recognizedType: return "the file type"
            case .corroboratedByProvider: return "on-device analysis agreeing"
            case .sharedProjectVocabulary: return "wording shared with related files"
            case .matchesUserHistory: return "how you have filed similar files before"
            }
        }

        /// Which reading of the file this signal came from.
        ///
        /// Two signals sharing a key are the same source speaking twice, not
        /// two sources agreeing — and the whole value of a noisy-OR is that
        /// it combines things which can fail *independently*.
        var sourceKey: String {
            switch self {
            case .filenameKeyword: return "filename"
            case .contentKeyword: return "content"
            case .recognizedType: return "type"
            case .corroboratedByProvider: return "provider"
            case .sharedProjectVocabulary: return "project"
            case .matchesUserHistory: return "history"
            }
        }
    }

    /// Nothing here is ever certain, so confidence is capped short of it.
    private static let ceiling = 0.95

    /// When independent sources disagree, the answer is less trustworthy than
    /// either source alone would suggest.
    private static let conflictPenalty = 0.7

    /// What a second and each further hit from the same source adds.
    private static let repeatStep = 0.06

    /// As far as repetition alone can carry one source. Well short of the
    /// overall ceiling: however many words of a filename agree, a filename on
    /// its own is never close to certain.
    private static let repeatCeiling = 0.8

    /// Combines signals. *Sources* are treated as independent chances of
    /// being right — `1 - ∏(1 - weight)` — and repeated hits from one source
    /// are not.
    public static func combine(_ signals: [Signal], conflicting: Bool = false) -> Double {
        guard !signals.isEmpty else { return 0.2 }

        let failure = weightsBySource(signals).reduce(1.0) { $0 * (1 - $1) }
        let combined = 1 - failure
        let adjusted = conflicting ? combined * conflictPenalty : combined
        return min(adjusted, ceiling)
    }

    /// One weight per source, with repeated hits from the same source folded
    /// into it rather than counted beside it.
    ///
    /// Noisy-OR is only honest about things that can fail separately, and
    /// four keywords read out of one filename cannot: a filename that is
    /// misleading is misleading in all of its words at once. Counting them
    /// as four chances took `invoice-template-blank.pdf` to 0.95 on the
    /// strength of a name that says the opposite — and, because
    /// `CategoryRefiner` only looks at files below its keyword threshold,
    /// spent that false certainty on never reading the file at all.
    ///
    /// Sorted so the product is formed in the same order every time. The
    /// arithmetic is associative, floating-point arithmetic is not, and an
    /// answer that changes in the last decimal between runs is one that
    /// cannot be tested.
    private static func weightsBySource(_ signals: [Signal]) -> [Double] {
        var strongest: [String: Double] = [:]
        var occurrences: [String: Int] = [:]
        for signal in signals {
            strongest[signal.sourceKey] = max(strongest[signal.sourceKey] ?? 0, signal.weight)
            occurrences[signal.sourceKey, default: 0] += 1
        }

        return strongest.map { source, weight in
            let repeats = Double((occurrences[source] ?? 1) - 1)
            // The ceiling applies to what repetition *adds*, never to the
            // signal's own weight: the personal model's margin can arrive
            // above it, and clamping that would quietly throw away the
            // strongest evidence Hoot has.
            return min(weight + repeatStep * repeats, max(weight, repeatCeiling))
        }
        .sorted()
    }

    /// A sentence naming what the confidence rests on, so the user can judge
    /// the reasoning rather than trusting a bare number.
    public static func explain(_ signals: [Signal], conflicting: Bool = false) -> String {
        guard !signals.isEmpty else { return "No clear evidence." }
        // One phrase per source, for the same reason confidence takes one
        // weight per source. Three keywords out of one filename are one
        // reason to believe something, and "the filename, the filename, and
        // the filename" would tell the user the opposite.
        var seen: Set<String> = []
        let names = signals
            .filter { seen.insert($0.sourceKey).inserted }
            .map(\.description)
        let joined: String
        switch names.count {
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) and \(names[1])"
        default: joined = names.dropLast().joined(separator: ", ") + ", and \(names.last!)"
        }
        let base = "Based on \(joined)."
        return conflicting ? base + " Signals disagreed, so confidence is reduced." : base
    }
}
