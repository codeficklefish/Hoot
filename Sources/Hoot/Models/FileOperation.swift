import Foundation

/// A completed file move, recorded so it can be shown in history and undone.
/// Every field needed to reverse the operation is captured here.
struct FileOperation: Identifiable, Codable, Hashable {
    let id: UUID
    let source: URL
    let destination: URL
    let performedAt: Date
    /// Directories created to make this move possible, deepest last. Undo
    /// removes them again only if they end up empty.
    let createdDirectories: [URL]

    var filename: String { destination.lastPathComponent }
}

/// One "Organize" action: all the moves the user approved together, undone
/// together as a unit.
struct OperationBatch: Identifiable, Codable, Hashable {
    let id: UUID
    let performedAt: Date
    let rootFolder: URL
    var operations: [FileOperation]
    /// Set once the batch has been reversed, so history can show it as undone.
    var undoneAt: Date?

    var isUndone: Bool { undoneAt != nil }
}
