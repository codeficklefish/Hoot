import Foundation
import HootKit
import HootPlatformMac

/// One file whose answer is already known.
struct LabelledFile {
    let file: FileItem
    /// The folder the user themselves put it in. That is the ground truth:
    /// they put it there, so that is where it belongs.
    let trueFolder: String
}

/// The user's own filing, read as an answer key.
///
/// No labelling work is asked of anyone, and nothing is moved. A file sitting
/// in `Finance` is a labelled example of what this person means by finance,
/// and a filename they have kept is a labelled example of a name worth
/// keeping. Every measurement in this target rests on one of those two facts.
enum EvaluationCorpus {

    /// The folder whose subfolders are the answer key.
    ///
    /// `HOOT_EVAL_ROOT` points it somewhere else. That exists because a real
    /// Downloads folder only exercises the paths it happens to reach — a
    /// small one never gets the personal model past its minimum corpus size,
    /// so the branch that consults it would go unrun and untested on the
    /// machine of the person most likely to change it.
    static var defaultRoot: URL {
        let override = ProcessInfo.processInfo.environment["HOOT_EVAL_ROOT"] ?? ""
        guard override.isEmpty else {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
    }

    /// Reads one level of subfolders as categories.
    static func gather(from root: URL = defaultRoot) -> [LabelledFile] {
        let fileManager = FileManager.default
        let subfolders = (try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        var labelled: [LabelledFile] = []
        for folder in subfolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            let contents = (try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )) ?? []
            for entry in contents {
                guard !FileAnalyzer.isIgnored(entry),
                      let file = FileAnalyzer.analyze(entry) else { continue }
                labelled.append(
                    LabelledFile(file: file, trueFolder: folder.lastPathComponent)
                )
            }
        }
        return labelled
    }

    /// The folder names the user actually keeps, which is the candidate list
    /// a provider is offered.
    static func folders(in corpus: [LabelledFile]) -> [String] {
        Set(corpus.map(\.trueFolder)).sorted()
    }

    /// Pads or truncates to a fixed column width, so a table stays a table.
    static func column(_ text: String, _ width: Int) -> String {
        String(text.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
