import Foundation

/// The durable log of every move Hoot has made.
///
/// Persisted to disk so history and undo survive relaunches — a move made
/// yesterday is still reversible today. Stored in Application Support rather
/// than in the watched folder, so Hoot never writes into the user's files.
public final class OperationHistory {
    public private(set) var batches: [OperationBatch] = []

    private let storeURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Keeps the log from growing without bound.
    private static let maximumBatches = 200

    public init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? Self.defaultStoreURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        let folder = base.appending(path: "Hoot", directoryHint: .isDirectory)
        // The log lists the full paths of the user's files, so keep both the
        // directory and its contents readable only by the owner. Other local
        // accounts have no business enumerating someone's documents.
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        return folder.appending(path: "history.json")
    }

    public func record(_ batch: OperationBatch) {
        batches.insert(batch, at: 0)
        if batches.count > Self.maximumBatches {
            batches = Array(batches.prefix(Self.maximumBatches))
        }
        save()
    }

    /// Marks a batch as reversed. The batch stays in the log as a record that
    /// it happened, rather than being erased.
    public func markUndone(_ batchID: UUID, at date: Date = Date()) {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        batches[index].undoneAt = date
        save()
    }

    /// Forgets every recorded batch. Only Hoot's own log is discarded —
    /// files that were already moved stay exactly where they are.
    public func clear() {
        batches = []
        save()
    }

    /// The most recent batch that can still be undone.
    public var mostRecentUndoable: OperationBatch? {
        batches.first { !$0.isUndone }
    }

    // MARK: - Persistence

    private func load() {
        // A log written by an older build may still be world-readable, and it
        // would keep those permissions until the next save. Tighten it now
        // rather than leaving the user's file paths exposed in the meantime.
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: storeURL.path
            )
        }

        guard let data = try? Data(contentsOf: storeURL) else { return }
        batches = (try? decoder.decode([OperationBatch].self, from: data)) ?? []
    }

    private func save() {
        do {
            let data = try encoder.encode(batches)
            try data.write(to: storeURL, options: .atomic)
            // An atomic write swaps in a fresh file, so ownership-only
            // permissions have to be reapplied after every save.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: storeURL.path
            )
        } catch {
            NSLog("Hoot: could not save history: \(error)")
        }
    }
}
