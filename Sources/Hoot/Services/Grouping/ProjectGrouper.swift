import Foundation

/// Finds files that belong together and names the project they form.
///
/// This is what separates Hoot from an extension sorter: `chapter1.docx`,
/// `survey_results.xlsx` and `research.pdf` share the token "thesis" (or land
/// in the same window of time) and should end up in one project folder rather
/// than three type folders.
///
/// Stage 2 uses filename tokens plus creation-date proximity. Semantic
/// grouping from file contents arrives in a later stage behind the same API.
struct ProjectGrouper {

    /// Files created within this window of each other are treated as
    /// potentially part of the same batch of work.
    private static let sameSessionWindow: TimeInterval = 60 * 60 * 6

    /// A token must appear in at least this many files to name a project.
    private static let minimumFilesPerProject = 2

    struct Group {
        let name: String
        let files: [FileItem]
        /// The shared token that justified the grouping, if any.
        let sharedToken: String?
        /// How strongly these files look related, 0...1.
        let cohesion: Double
    }

    /// Partitions `files` into project groups plus leftovers that showed no
    /// relationship to anything else.
    func group(_ files: [FileItem]) -> (groups: [Group], ungrouped: [FileItem]) {
        guard files.count > 1 else { return ([], files) }

        // Index files by each distinctive token in their name.
        var filesByToken: [String: [FileItem]] = [:]
        for file in files {
            for token in Set(FilenameTokenizer.tokens(in: file.filename)) {
                filesByToken[token, default: []].append(file)
            }
        }

        // Prefer tokens that cover more files; a token shared by four files is
        // a better project name than one shared by two.
        let candidateTokens = filesByToken
            .filter { $0.value.count >= Self.minimumFilesPerProject }
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count
                    ? lhs.value.count > rhs.value.count
                    : lhs.key < rhs.key
            }

        var claimed: Set<URL> = []
        var groups: [Group] = []

        for (token, tokenFiles) in candidateTokens {
            let available = tokenFiles.filter { !claimed.contains($0.url) }
            guard available.count >= Self.minimumFilesPerProject else { continue }

            available.forEach { claimed.insert($0.url) }
            groups.append(
                Group(
                    name: FilenameTokenizer.displayName(for: token),
                    files: available.sorted { $0.filename < $1.filename },
                    sharedToken: token,
                    cohesion: Self.cohesion(of: available, sharedToken: true)
                )
            )
        }

        let ungrouped = files.filter { !claimed.contains($0.url) }
        return (groups, ungrouped)
    }

    /// Confidence that a set of files really belongs together: a shared
    /// filename token is the main signal, reinforced when the files were also
    /// created around the same time.
    private static func cohesion(of files: [FileItem], sharedToken: Bool) -> Double {
        var score = sharedToken ? 0.75 : 0.4

        let dates = files.compactMap(\.createdAt).sorted()
        if let first = dates.first, let last = dates.last,
           last.timeIntervalSince(first) <= sameSessionWindow {
            score += 0.15
        }

        // More corroborating files is a stronger signal, up to a ceiling.
        score += min(Double(files.count - 2) * 0.03, 0.09)

        return min(score, 0.99)
    }
}
