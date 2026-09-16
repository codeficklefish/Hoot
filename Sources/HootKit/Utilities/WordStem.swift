import Foundation

/// Reduces a word to the form it shares with its own plural.
///
/// `invoice` and `invoices` are the same claim about a file, and comparing
/// them as plain strings is why `Invoices-2024.pdf` matched no rule at all
/// while `invoice-2024.pdf` reached Finance. The words this costs are the
/// commonest things in a downloads folder — receipts, taxes, contracts,
/// statements, results.
///
/// Only the plural is removed. This is not a general stemmer: it does not
/// touch tense, comparatives or derivations, because over-stemming fails
/// silently and permanently. `address` reduced to `addres` would match
/// nothing, and nobody would ever see why. So every rule below refuses when
/// it cannot be sure.
public enum WordStem {

    /// Endings that look like a plural and are not. English piles these up:
    /// `address` and `class` end in a doubled s, `analysis` and `thesis` are
    /// Greek singulars, `status` and `campus` Latin ones.
    ///
    /// `-as` and `-os` are deliberately absent, though they look like they
    /// belong: `areas`, `cameras`, `ideas`, `photos` and `videos` are all
    /// ordinary plurals, and guarding those endings would lose more than the
    /// handful of singulars it saved.
    private static let notPlural = ["ss", "is", "us"]

    /// Nouns whose plural is spelled with `es` because the singular already
    /// ends in a hiss: `taxes`, `boxes`, `churches`, `responses`.
    private static let hissing = ["ses", "xes", "zes", "ches", "shes"]

    /// Below this there is not enough word left to judge. `bus` and `gas` are
    /// not plurals, and neither is anything else this short.
    private static let shortestStemmable = 4

    /// The singular of `word`, or `word` unchanged when it is already
    /// singular or cannot be judged. Expects a lowercased token.
    public static func stem(_ word: String) -> String {
        guard word.count >= shortestStemmable, word.hasSuffix("s") else { return word }
        guard !notPlural.contains(where: word.hasSuffix) else { return word }

        // `policies` → `policy`. Length-guarded so `ties` and `dies` keep
        // their own spelling instead of becoming `ty` and `dy`.
        if word.hasSuffix("ies"), word.count >= 5 {
            return String(word.dropLast(3)) + "y"
        }
        if hissing.contains(where: word.hasSuffix) {
            return String(word.dropLast(2))
        }
        return String(word.dropLast())
    }
}
