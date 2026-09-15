import Foundation

/// One proposed file move, awaiting the user's approval. Nothing in a plan
/// has touched the disk yet.
public struct PlannedMove: Identifiable {
    public init(file: FileItem, classification: ClassificationResult,
                destinationFolder: String, roleSubfolder: String?,
                destinationName: String, isApproved: Bool) {
        self.file = file
        self.classification = classification
        self.destinationFolder = destinationFolder
        self.roleSubfolder = roleSubfolder
        self.destinationName = destinationName
        self.isApproved = isApproved
    }

    public let id = UUID()
    public let file: FileItem
    public let classification: ClassificationResult
    /// Top-level folder inside the watched directory, e.g. "Thesis".
    /// Stored separately from the role so renaming a group only has to
    /// change this one value on each of its moves.
    public var destinationFolder: String
    /// Optional role folder within the project, e.g. "Data".
    public var roleSubfolder: String?
    public var destinationName: String
    /// Whether this move is included when the user organizes.
    public var isApproved: Bool

    /// Path relative to the watched folder, e.g. "Thesis/Data".
    public var destinationSubpath: String {
        guard let roleSubfolder, !roleSubfolder.isEmpty else { return destinationFolder }
        return "\(destinationFolder)/\(roleSubfolder)"
    }

    public func destinationURL(root: URL) -> URL {
        root.appending(path: destinationSubpath).appending(path: destinationName)
    }
}

/// A set of proposed moves, grouped the way they'll be presented for review.
public struct PlannedGroup: Identifiable {
    public init(name: String, proposedName: String, rationale: String, moves: [PlannedMove]) {
        self.name = name
        self.proposedName = proposedName
        self.rationale = rationale
        self.moves = moves
    }

    public let id = UUID()
    /// The destination folder for this group. Editable by the user in review.
    public var name: String
    /// What Hoot originally proposed, kept so a rename can be remembered
    /// as "when you suggest X, I want Y".
    public let proposedName: String
    /// Why these files were put together, shown in the review UI.
    public let rationale: String
    public var moves: [PlannedMove]

    public var approvedCount: Int { moves.filter(\.isApproved).count }
}

public struct OrganizationPlan {
    public init(root: URL, groups: [PlannedGroup], skipped: [(file: FileItem, reason: String)]) {
        self.root = root
        self.groups = groups
        self.skipped = skipped
    }

    public let root: URL
    public var groups: [PlannedGroup]
    /// Files deliberately left alone because confidence was too low.
    public let skipped: [(file: FileItem, reason: String)]

    public var allMoves: [PlannedMove] { groups.flatMap(\.moves) }
    public var approvedMoves: [PlannedMove] { allMoves.filter(\.isApproved) }
    public var isEmpty: Bool { groups.isEmpty }

    /// One destination and how many files are headed for it.
    public struct WaitingEntry: Equatable, Sendable {
        public init(label: String, count: Int) {
            self.label = label
            self.count = count
        }

        public let label: String
        public let count: Int
    }

    /// What the user calls the files nothing is going to happen to. Named
    /// here because three surfaces show that count and they have to agree on
    /// the word as well as the number.
    public static let leftAloneLabel = "Left alone"

    /// What is waiting, one entry per destination, ending with the files the
    /// plan decided to leave where they are.
    ///
    /// In the engine rather than in the menu bar view because it is the same
    /// question the review window and the notch HUD answer, and three
    /// surfaces working it out separately is how they came to disagree: the
    /// popover counted every file it had found and labelled it with the
    /// classifier's category, so a file this plan had decided not to touch
    /// still appeared under a destination, as though it were about to move.
    public var waiting: [WaitingEntry] {
        var entries = groups
            .map { WaitingEntry(label: $0.name, count: $0.approvedCount) }
            .filter { $0.count > 0 }
        if !skipped.isEmpty {
            entries.append(WaitingEntry(label: Self.leftAloneLabel, count: skipped.count))
        }
        return entries
    }
}
