import Foundation

/// Something the user needs to know about, rather than a line in a log.
///
/// Hoot does its work in the background, so a failure that only reaches the
/// console is indistinguishable from the app doing nothing. Anything that
/// changes what Hoot can do for someone belongs here.
public struct UserFacingIssue: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    /// What the user can actually do about it, when there is something.
    public let suggestion: String?
    public let occurredAt: Date
    public let severity: Severity

    public enum Severity {
        /// Hoot carried on with reduced ability.
        case warning
        /// Something the user asked for did not happen.
        case failure

        public var symbolName: String {
            switch self {
            case .warning: return "exclamationmark.triangle"
            case .failure: return "xmark.octagon"
            }
        }
    }

    public init(title: String, suggestion: String? = nil, severity: Severity = .failure) {
        self.title = title
        self.suggestion = suggestion
        self.occurredAt = Date()
        self.severity = severity
    }
}
