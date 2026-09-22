import Foundation

/// How a set of files is split into requests the on-device model can hold.
///
/// The model's context has to carry the prompt *and* the answer, and the
/// answer is a category and a reason for every file in the request — so the
/// budget is spent roughly twice over. Splitting by file count alone does not
/// bound it, because an excerpt runs from nothing to `excerptLength`
/// characters: eighteen filenames is a small request, eighteen filenames each
/// carrying six hundred characters of text is not.
///
/// That is not hypothetical. The category request was split eighteen at a
/// time, and on a real Downloads folder it threw `Exceeded model context
/// window size` every time — which `CategoryRefiner` caught, logged, and
/// turned into "the model had nothing to say". Every file fell back to
/// filename rules while the interface went on offering to read them. It only
/// appeared once a folder was big enough to be worth using Hoot on.
///
/// In the engine rather than beside the provider because it is arithmetic
/// with a product decision in it, and this is where the suite can hold it to
/// account.
public enum RequestBatch {

    /// Characters of prompt one request may carry.
    ///
    /// A budget in characters rather than tokens: tokens are the model's unit
    /// and it will not tell us the count in advance, but they run about four
    /// characters each, and this is a ceiling to stay under rather than a
    /// figure to hit. Deliberately well short of the window, because the
    /// answer has to fit beside the question.
    public static let characterBudget = 2_600

    /// And a cap on files regardless of how short their excerpts are, because
    /// the *answer* grows with the file count even when the question does not.
    /// Eight is what the naming request settled on for the same reason.
    public static let maximumFiles = 8

    /// What one file is expected to cost the prompt: its name, its excerpt,
    /// and the labelling around both.
    public static func cost(of file: FileDescriptor) -> Int {
        let labels = 24
        return file.filename.count + (file.excerpt?.count ?? 0) + labels
    }

    /// Splits files into requests, each within both limits.
    ///
    /// A single file whose excerpt alone exceeds the budget still gets its own
    /// request rather than being dropped: it is over budget either way, and
    /// the provider refusing one file is a better failure than the batch it
    /// was travelling in taking eight others down with it.
    public static func split(
        _ files: [FileDescriptor],
        budget: Int = characterBudget,
        maximum: Int = maximumFiles
    ) -> [[FileDescriptor]] {
        var batches: [[FileDescriptor]] = []
        var current: [FileDescriptor] = []
        var spent = 0

        for file in files {
            let price = cost(of: file)
            let full = current.count >= maximum || (!current.isEmpty && spent + price > budget)
            if full {
                batches.append(current)
                current = []
                spent = 0
            }
            current.append(file)
            spent += price
        }

        if !current.isEmpty { batches.append(current) }
        return batches
    }
}
