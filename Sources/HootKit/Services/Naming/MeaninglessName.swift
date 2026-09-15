import Foundation

/// Whether a filename says anything at all about the file under it.
///
/// The premise of the whole app is that the name is the thing that failed —
/// a boarding pass saved as `3721984.pdf`, a résumé as `12312312312312.docx`,
/// a scan as `ASJKDHASDASD.pdf`, a download as `------.pdf`. Those are the
/// files where a proposed name is an improvement rather than an intrusion,
/// and this is where that line is drawn.
///
/// The test is deliberately lopsided. Deciding a meaningless name is
/// meaningful only costs a rename that never happens; deciding someone's
/// `Q3 budget.xlsx` says nothing would put a model's invention where a
/// person's own words used to be. So a name is meaningless only when
/// *nothing* in it reads as a word.
///
/// `FilenameTokenizer` is deliberately not reused here, though it answers a
/// similar question for the classifier. It lowercases and splits on humps,
/// and those two things are exactly what identifies the hardest names in a
/// real Downloads folder: `HRzRhOQX0AgotkS.jpeg` is a CDN id because of its
/// case, not its spelling, and that evidence is gone by the time the
/// tokenizer has finished with it.
public enum MeaninglessName {

    /// True when nothing in `filename` carries information about the file.
    public static func applies(to filename: String) -> Bool {
        let base = (filename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A short name is usually an acronym, and an acronym says plenty:
        // CV, NDA, W2. Both rules below would call these gibberish — the
        // first for being too short, the second for having no vowel — so the
        // exemption has to come before either of them.
        if base.count >= 2, base.count <= 4, base.contains(where: \.isLetter) {
            return false
        }

        let words = base.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !words.isEmpty else { return true }
        return !words.contains(where: readsAsWord)
    }

    // MARK: - Words that are not evidence

    /// Words that appear in a filename precisely because nobody chose one.
    /// A file called `unnamed.jpg` is named after the absence of a name.
    private static let emptyWords: Set<String> = [
        "untitled", "unnamed", "unknown", "image", "images", "img", "photo",
        "photos", "picture", "pic", "scan", "scanned", "screenshot", "screen",
        "shot", "capture", "document", "documents", "doc", "docs", "file",
        "files", "download", "downloads", "copy", "final", "draft", "new",
        "temp", "tmp", "export", "output", "attachment", "version", "untitled",
        // Camera and phone prefixes. The number beside them is a counter, not
        // a date or an amount, and says nothing either.
        "dsc", "dscn", "dcim", "pxl", "mvimg", "vid", "mov", "rec"
    ]

    // MARK: - What a word looks like

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// Rows of a keyboard. A run along one of them is a pair of hands, not a
    /// word. Five characters rather than four because "erty" sits inside
    /// "property" and "liberty", and renaming someone's `property.pdf` on
    /// that basis would be exactly the mistake this file exists to avoid.
    private static let keyboardRuns: Set<String> = {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890"]
        var runs: Set<String> = []
        for row in rows {
            let characters = Array(row)
            for start in 0...(characters.count - 5) {
                let run = String(characters[start..<(start + 5)])
                runs.insert(run)
                runs.insert(String(run.reversed()))
            }
        }
        return runs
    }()

    /// English piles consonants up at the end of a word and nowhere else:
    /// "strengths", "twelfths", "warmths" all end in five of them. The same
    /// five in the middle of a word — "asjkdhasdasd" — is a hand resting on
    /// the keyboard. Where the run sits is the only thing separating the two,
    /// so the length alone is never enough to decide.
    private static let impossibleConsonantRun = 5

    /// Long enough that a hexadecimal reading is not a coincidence: "decade"
    /// and "faced" are hex by accident, an eight-character id is not.
    private static let hexadecimalBlobLength = 8

    /// A capital arriving mid-word is ordinary once — "DaVinci", "iPhone",
    /// "McGraw". Twice is a machine shuffling characters.
    private static let deliberateHumps = 2

    private static func readsAsWord(_ word: String) -> Bool {
        // These rules can only read Latin script. A Japanese or Greek filename
        // is not gibberish merely because they cannot, so anything outside
        // ASCII is taken at its word.
        guard word.allSatisfy(\.isASCII) else { return true }

        let lowercased = word.lowercased()
        guard !emptyWords.contains(lowercased) else { return false }

        let letters = lowercased.filter(\.isLetter)
        let digits = lowercased.filter(\.isNumber)

        guard letters.count >= 3 else { return false }
        // Letters have to outnumber digits outright. "invoice2024" is a word
        // with a year after it; "WYAA1234" is an identifier with a few
        // letters in it, and the halfway point is where one becomes the other.
        guard letters.count > digits.count else { return false }
        guard !isHexadecimalBlob(lowercased) else { return false }
        guard letters.contains(where: vowels.contains) else { return false }
        guard !runsAlongKeyboard(lowercased) else { return false }
        guard !hasImpossibleConsonantRun(letters) else { return false }
        guard humps(in: word) < deliberateHumps else { return false }
        return true
    }

    private static func isHexadecimalBlob(_ word: String) -> Bool {
        word.count >= hexadecimalBlobLength
            && word.allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    /// A consonant run long enough to be unpronounceable, anywhere except at
    /// the very end of the word, where English genuinely puts them.
    private static func hasImpossibleConsonantRun(_ letters: String) -> Bool {
        var run = 0
        for (offset, letter) in letters.enumerated() {
            if vowels.contains(letter) {
                run = 0
                continue
            }
            run += 1
            guard run >= impossibleConsonantRun else { continue }
            // Reaching the length is only damning if the word carries on
            // afterwards; a coda is allowed to be this ugly.
            if offset < letters.count - 1 { return true }
        }
        return false
    }

    private static func runsAlongKeyboard(_ word: String) -> Bool {
        let characters = Array(word)
        guard characters.count >= 5 else { return false }
        for start in 0...(characters.count - 5) {
            if keyboardRuns.contains(String(characters[start..<(start + 5)])) { return true }
        }
        return false
    }

    /// Lowercase-to-uppercase transitions inside one word.
    private static func humps(in word: String) -> Int {
        var count = 0
        var previous: Character?
        for character in word {
            if let previous, previous.isLowercase, character.isUppercase { count += 1 }
            previous = character
        }
        return count
    }
}
