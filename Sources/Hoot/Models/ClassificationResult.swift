import Foundation

/// The output of any FileClassifier (rule-based, local LLM, or remote API).
/// This is the one shape every classifier implementation must produce,
/// which is what lets the AI provider be swapped out later.
struct ClassificationResult: Identifiable, Hashable {
    let id: UUID
    let fileID: UUID
    let category: String
    let project: String?
    let suggestedFolder: String
    let suggestedName: String
    let confidence: Double
    let reason: String

    init(
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
    static let lowConfidenceThreshold = 0.5

    var isLowConfidence: Bool {
        confidence < Self.lowConfidenceThreshold
    }
}
