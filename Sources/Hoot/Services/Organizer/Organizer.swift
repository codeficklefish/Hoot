import Foundation

enum OrganizerError: LocalizedError {
    case sourceMissing(URL)
    case destinationOccupied(URL)
    case escapesWatchedFolder(URL)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let url):
            return "\(url.lastPathComponent) is no longer at its original location."
        case .destinationOccupied(let url):
            return "Something already exists at \(url.path)."
        case .escapesWatchedFolder(let url):
            return "“\(url.lastPathComponent)” leads outside the watched folder, so Hoot won't move files into it."
        }
    }
}

/// Performs the file moves in an approved plan, and reverses them on undo.
///
/// Every operation here is deliberately conservative: files are only ever
/// moved, never copied-and-deleted and never overwritten. If a name is taken
/// at the destination, a free variant is chosen instead of clobbering it.
struct Organizer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Executes the approved moves. Returns a batch describing what happened,
    /// along with any moves that failed (the rest still go through).
    func organize(_ plan: OrganizationPlan) -> (batch: OperationBatch, failures: [(PlannedMove, Error)]) {
        var operations: [FileOperation] = []
        var failures: [(PlannedMove, Error)] = []

        for move in plan.approvedMoves {
            do {
                operations.append(try perform(move, root: plan.root))
            } catch {
                failures.append((move, error))
            }
        }

        let batch = OperationBatch(
            id: UUID(),
            performedAt: Date(),
            rootFolder: plan.root,
            operations: operations,
            undoneAt: nil
        )
        return (batch, failures)
    }

    private func perform(_ move: PlannedMove, root: URL) throws -> FileOperation {
        let source = move.file.url
        guard fileManager.fileExists(atPath: source.path) else {
            throw OrganizerError.sourceMissing(source)
        }

        let folder = root.appending(path: move.destinationSubpath)

        // A destination component can be a symlink pointing anywhere on disk —
        // planted by an extracted archive, or created by the user. Following
        // it would move files out of the folder Hoot was given permission to
        // organize, so the resolved path is required to stay inside the root.
        try verifyContained(folder, within: root)

        let createdDirectories = try makeDirectories(at: folder)

        let destination = availableURL(
            in: folder,
            preferredName: move.destinationName
        )

        // Re-check after creating directories, in case a component resolved
        // differently once it existed.
        try verifyContained(destination, within: root)

        try fileManager.moveItem(at: source, to: destination)

        return FileOperation(
            id: UUID(),
            source: source,
            destination: destination,
            performedAt: Date(),
            createdDirectories: createdDirectories
        )
    }

    /// Reverses a batch, newest move first. Each file goes back to exactly
    /// where it came from; directories Hoot created are cleaned up if empty.
    func undo(_ batch: OperationBatch) -> (restored: [FileOperation], failures: [(FileOperation, Error)]) {
        var restored: [FileOperation] = []
        var failures: [(FileOperation, Error)] = []

        for operation in batch.operations.reversed() {
            do {
                guard fileManager.fileExists(atPath: operation.destination.path) else {
                    throw OrganizerError.sourceMissing(operation.destination)
                }
                // Refuse to undo onto an occupied original path rather than
                // overwriting whatever now lives there.
                guard !fileManager.fileExists(atPath: operation.source.path) else {
                    throw OrganizerError.destinationOccupied(operation.source)
                }
                try fileManager.moveItem(at: operation.destination, to: operation.source)
                restored.append(operation)
            } catch {
                failures.append((operation, error))
            }
        }

        // Deepest first, so nested folders empty out before their parents.
        let directories = Set(batch.operations.flatMap(\.createdDirectories))
            .sorted { $0.pathComponents.count > $1.pathComponents.count }
        for directory in directories {
            removeIfEmpty(directory)
        }

        return (restored, failures)
    }

    // MARK: - Safety helpers

    /// Fails unless `url` genuinely lives inside `root` once every symlink in
    /// the path has been resolved.
    private func verifyContained(_ url: URL, within root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        // Resolve the deepest part of the path that exists; components Hoot is
        // about to create can't be symlinks yet.
        var existing = url
        while !fileManager.fileExists(atPath: existing.path),
              existing.pathComponents.count > 1,
              existing.deletingLastPathComponent() != existing {
            existing = existing.deletingLastPathComponent()
        }
        let resolved = existing.resolvingSymlinksInPath().standardizedFileURL

        guard resolved.path == resolvedRoot.path
                || resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw OrganizerError.escapesWatchedFolder(url)
        }
    }

    /// Creates `folder` if needed, returning only the directories that did not
    /// already exist so undo never removes a folder the user had themselves.
    private func makeDirectories(at folder: URL) throws -> [URL] {
        var missing: [URL] = []
        var current = folder
        while !fileManager.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            missing.append(current)
            current = current.deletingLastPathComponent()
        }
        guard !missing.isEmpty else { return [] }

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return missing.reversed()
    }

    /// Finds a free filename in `folder`, appending " 2", " 3"… when taken.
    /// Never returns a path that already exists.
    private func availableURL(in folder: URL, preferredName: String) -> URL {
        let candidate = folder.appending(path: preferredName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var counter = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let url = folder.appending(path: name)
            if !fileManager.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }

    private func removeIfEmpty(_ directory: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        // .DS_Store alone doesn't count as the user having put something here.
        let meaningful = contents.filter { $0 != ".DS_Store" }
        guard meaningful.isEmpty else { return }
        try? fileManager.removeItem(at: directory)
    }
}
