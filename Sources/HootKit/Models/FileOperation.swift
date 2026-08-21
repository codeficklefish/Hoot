import Foundation

/// A completed file move, recorded so it can be shown in history and undone.
/// Every field needed to reverse the operation is captured here.
public struct FileOperation: Identifiable, Codable, Hashable {
    public init(id: UUID, source: URL, destination: URL, performedAt: Date,
                createdDirectories: [URL]) {
        self.id = id
        self.source = source
        self.destination = destination
        self.performedAt = performedAt
        self.createdDirectories = createdDirectories
    }

    public let id: UUID
    public let source: URL
    public let destination: URL
    public let performedAt: Date
    /// Directories created to make this move possible, deepest last. Undo
    /// removes them again only if they end up empty.
    public let createdDirectories: [URL]

    public var filename: String { destination.lastPathComponent }
}

/// One "Organize" action: all the moves the user approved together, undone
/// together as a unit.
public struct OperationBatch: Identifiable, Codable, Hashable {
    public init(id: UUID, performedAt: Date, rootFolder: URL,
                operations: [FileOperation], undoneAt: Date?) {
        self.id = id
        self.performedAt = performedAt
        self.rootFolder = rootFolder
        self.operations = operations
        self.undoneAt = undoneAt
    }

    public let id: UUID
    public let performedAt: Date
    public let rootFolder: URL
    public var operations: [FileOperation]
    /// Set once the batch has been reversed, so history can show it as undone.
    public var undoneAt: Date?

    public var isUndone: Bool { undoneAt != nil }
}
