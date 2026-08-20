import Foundation

/// One proposed file move, awaiting the user's approval. Nothing in a plan
/// has touched the disk yet.
struct PlannedMove: Identifiable {
    let id = UUID()
    let file: FileItem
    let classification: ClassificationResult
    /// Top-level folder inside the watched directory, e.g. "Thesis".
    /// Stored separately from the role so renaming a group only has to
    /// change this one value on each of its moves.
    var destinationFolder: String
    /// Optional role folder within the project, e.g. "Data".
    var roleSubfolder: String?
    var destinationName: String
    /// Whether this move is included when the user organizes.
    var isApproved: Bool

    /// Path relative to the watched folder, e.g. "Thesis/Data".
    var destinationSubpath: String {
        guard let roleSubfolder, !roleSubfolder.isEmpty else { return destinationFolder }
        return "\(destinationFolder)/\(roleSubfolder)"
    }

    func destinationURL(root: URL) -> URL {
        root.appending(path: destinationSubpath).appending(path: destinationName)
    }
}

/// A set of proposed moves, grouped the way they'll be presented for review.
struct PlannedGroup: Identifiable {
    let id = UUID()
    /// The destination folder for this group. Editable by the user in review.
    var name: String
    /// What Hoot originally proposed, kept so a rename can be remembered
    /// as "when you suggest X, I want Y".
    let proposedName: String
    /// Why these files were put together, shown in the review UI.
    let rationale: String
    var moves: [PlannedMove]

    var approvedCount: Int { moves.filter(\.isApproved).count }
}

struct OrganizationPlan {
    let root: URL
    var groups: [PlannedGroup]
    /// Files deliberately left alone because confidence was too low.
    let skipped: [(file: FileItem, reason: String)]

    var allMoves: [PlannedMove] { groups.flatMap(\.moves) }
    var approvedMoves: [PlannedMove] { allMoves.filter(\.isApproved) }
    var isEmpty: Bool { groups.isEmpty }
}
