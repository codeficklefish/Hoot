import Foundation
import HootKit
import HootPlatformMac

// Measures Hoot against folders the user organized themselves. Reads their
// files; moves nothing, writes nothing.
//
// Three measurements, each answering a different question:
//
//   folders      does a file end up where you would have put it?
//   meaningless  which of the names you kept would Hoot offer to overwrite?
//   names        can Hoot recover a name you chose, from the file's text?
//
// Named on the command line to run one; all three by default. A number sets
// how many files the naming run asks about, which is the slow one — every
// file costs a model round trip.

let arguments = CommandLine.arguments.dropFirst()
let requested = Set(arguments.filter { Int($0) == nil })
let wanted = requested.isEmpty ? ["folders", "meaningless", "names"] : requested
let namingLimit = arguments.compactMap(Int.init).first ?? 40

let corpus = EvaluationCorpus.gather()
print("labelled files: \(corpus.count)")
print("your folders: \(EvaluationCorpus.folders(in: corpus).joined(separator: ", "))")

let finished = DispatchSemaphore(value: 0)
Task {
    if corpus.isEmpty {
        print("\nNothing to measure: \(EvaluationCorpus.defaultRoot.path) has no "
            + "subfolders with files in them yet.")
    } else {
        if wanted.contains("folders") { await evaluateFolders(corpus) }
        if wanted.contains("meaningless") { evaluateMeaninglessNames(corpus) }
        if wanted.contains("names") { await evaluateProposedNames(corpus, limit: namingLimit) }
    }
    finished.signal()
}
finished.wait()
