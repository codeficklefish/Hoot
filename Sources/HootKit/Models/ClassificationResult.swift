import Foundation

/// Where one file belongs, and how much that answer is trusted.
///
/// Every source of an answer produces this same shape — the filename rules,
/// the personal model learned from the user's folders, and a provider's
/// suggestion once `CategoryRefiner` has arbitrated it — so a later stage can
/// replace an earlier one's answer without the caller knowing which spoke.
public struct ClassificationResult: Identifiable, Hashable {
    public let id: UUID
    public let fileID: UUID
    public let category: String
    public let project: String?
    public let suggestedFolder: String
    public let suggestedName: String
    public let confidence: Double
    public let reason: String

    public init(
        fileID: UUID,
        category: String,
        project: String?,
        suggestedFolder: String,
        suggestedName: String,
        confidence: Double,
        reason: String
    ) {
        self.id = UUID()
        self.fileID = fileID
        self.category = category
        self.project = project
        self.suggestedFolder = suggestedFolder
        self.suggestedName = suggestedName
        self.confidence = confidence
        self.reason = reason
    }

    /// Below this, Hoot should leave the file untouched rather than guess.
    public static let lowConfidenceThreshold = 0.5

    public var isLowConfidence: Bool {
        confidence < Self.lowConfidenceThreshold
    }
}
