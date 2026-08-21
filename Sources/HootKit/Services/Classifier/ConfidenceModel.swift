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
        /// It resembles files the user has already filed in a folder of theirs.
        case matchesUserHistory

        var weight: Double {
            switch self {
            case .filenameKeyword: return 0.62
            case .contentKeyword: return 0.58
            // Enough to file by type, but it says nothing about the subject.
            case .recognizedType: return 0.55
            case .corroboratedByProvider: return 0.60
            case .sharedProjectVocabulary: return 0.50
            // The strongest single signal available: not a guess about what
            // the file is, but evidence of what this person actually does.
            case .matchesUserHistory: return 0.70
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
    }

    /// Nothing here is ever certain, so confidence is capped short of it.
    private static let ceiling = 0.95

    /// When independent sources disagree, the answer is less trustworthy than
    /// either source alone would suggest.
    private static let conflictPenalty = 0.7

    /// Combines signals. Each is treated as an independent chance of being
    /// right: `1 - ∏(1 - weight)`.
    public static func combine(_ signals: [Signal], conflicting: Bool = false) -> Double {
        guard !signals.isEmpty else { return 0.2 }

        let failure = signals.reduce(1.0) { $0 * (1 - $1.weight) }
        let combined = 1 - failure
        let adjusted = conflicting ? combined * conflictPenalty : combined
        return min(adjusted, ceiling)
    }

    /// A sentence naming what the confidence rests on, so the user can judge
    /// the reasoning rather than trusting a bare number.
    public static func explain(_ signals: [Signal], conflicting: Bool = false) -> String {
        guard !signals.isEmpty else { return "No clear evidence." }
        let names = signals.map(\.description)
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
