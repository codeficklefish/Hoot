import Foundation

/// Whether a proposed name is actually carried by the text it was supposed to
/// come from.
///
/// The naming instructions tell the model to use "only names, dates, places,
/// subjects and amounts that appear in the text, invent nothing" — and until
/// this existed, that sentence *was* the enforcement. Everything else about a
/// proposed name is checked: that it is safe as a path, that it is not a
/// placeholder, that it is not as meaningless as the name it replaces. The
/// one rule the feature rests on was the one nothing tested.
///
/// The check is mechanical and deliberately literal. Every word of the
/// proposal has to appear in the excerpt the model was shown, and so does
/// every long number. A word the model merely *expected* to be true — the
/// shop it assumes a receipt came from, a year it rounded off — fails, and
/// that is the point. A filename is a claim about what a file is, and it is
/// the thing the user will later go looking for the file by, so an invention
/// here is the most expensive kind: quiet, plausible, and only discovered
/// when the file cannot be found.
///
/// It is stricter than the prompt in one direction and looser in another. A
/// model that names a receipt "Grocery receipt" when the text never says
/// "grocery" is refused, even though a person might have called it that.
/// Short numbers are not checked at all, because two digits match almost any
/// text and a rule that always passes is worse than no rule.
public enum NameGrounding {

    /// Below this a digit run is too common to be evidence of anything: `03`
    /// appears inside `2003`. At three digits a match is a real one — a year,
    /// an amount, a reference number.
    private static let shortestCheckableNumber = 3

    /// True when every word and every long number in `name` can be found in
    /// `excerpt`.
    ///
    /// - Parameters:
    ///   - name: the proposed filename, extension included or not.
    ///   - excerpt: the text the model was shown for this file — not a fresh
    ///     read of it. Checking a name against evidence the model never saw
    ///     would refuse names that were honestly derived from what it did.
    public static func isSupported(_ name: String, by excerpt: String) -> Bool {
        let proposal = (name as NSString).deletingPathExtension

        // Stemmed on both sides for the same reason the classifier stems:
        // a receipt whose text says "TAXES" supports the name "tax", and
        // refusing it would be a spelling rule masquerading as a safety one.
        let evidence = Set(FilenameTokenizer.tokens(in: excerpt).map(WordStem.stem))
        for word in FilenameTokenizer.tokens(in: proposal) {
            guard evidence.contains(WordStem.stem(word)) else { return false }
        }

        // `FilenameTokenizer` drops digits, so a hallucinated year or amount
        // would pass the loop above untouched — and a wrong date in a
        // filename is exactly as misleading as a wrong word.
        for number in longNumbers(in: proposal) {
            guard excerpt.contains(number) else { return false }
        }

        return true
    }

    /// Runs of digits long enough to mean something on their own.
    private static func longNumbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= shortestCheckableNumber }
    }
}
