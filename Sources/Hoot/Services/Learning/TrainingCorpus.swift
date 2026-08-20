import Foundation

/// Turns folders the user has already organized into training examples.
///
/// No labelling work is asked of anyone: a file sitting in `Finance` is a
/// labelled example of what this person considers finance. The corpus is
/// gathered from filenames and metadata only — fast enough to rebuild on
/// demand over a few hundred files, and it opens nothing.
struct TrainingCorpus {

    /// Folders that describe storage rather than subject, and would teach the
    /// classifier nothing about what the user means.
    private static let unhelpfulFolders: Set<String> = [
        "downloads", "desktop", "documents", "untitled folder", "new folder",
        "temp", "tmp", "misc", "unsorted", "previous versions"
    ]

    /// Reads one level of subfolders as categories.
    ///
    /// - Parameter root: the folder whose subfolders are the user's categories.
    static func gather(from root: URL, fileManager: FileManager = .default) -> [LearnedClassifier.Sample] {
        let subfolders = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var samples: [LearnedClassifier.Sample] = []

        for folder in subfolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            let name = folder.lastPathComponent
            guard !Self.unhelpfulFolders.contains(name.lowercased()) else { continue }

            // Include files one level down too, so `Thesis/Data/x.xlsx` still
            // counts as an example of `Thesis`.
            let contents = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            var depthGuard = 0
            while let next = contents?.nextObject() as? URL, depthGuard < 5000 {
                depthGuard += 1
                guard !FileAnalyzer.isIgnored(next),
                      let file = FileAnalyzer.analyze(next) else { continue }
                samples.append(
                    LearnedClassifier.Sample(features: features(for: file), folder: name)
                )
            }
        }

        return samples
    }

    /// What the classifier gets to see about a file.
    ///
    /// Filename words carry the user's own vocabulary — an author's name, a
    /// client, a course code. Extension and kind are included so that files
    /// with no usable name still contribute something, which matters because
    /// camera-roll photos are exactly the files whose names say nothing.
    static func features(for file: FileItem) -> [String] {
        var features = FilenameTokenizer.tokens(in: file.filename)
        features.append("ext:\(file.fileExtension.lowercased())")
        features.append("kind:\(file.kind)")
        return features
    }
}
