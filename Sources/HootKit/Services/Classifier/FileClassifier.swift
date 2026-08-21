import Foundation

/// The single seam between Hoot's file pipeline and whatever does the
/// actual thinking about where a file belongs — a rule-based fallback
/// today, a local or remote AI model later. Nothing else in the app
/// should know which one is in use.
public protocol FileClassifier {
    func classify(_ file: FileItem) async throws -> ClassificationResult
}
