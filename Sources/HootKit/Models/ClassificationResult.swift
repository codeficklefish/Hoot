import Foundation

/// The output of any FileClassifier (rule-based, local LLM, or remote API).
/// This is the one shape every classifier implementation must produce,
/// which is what lets the AI provider be swapped out later.
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
