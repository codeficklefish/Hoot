import Foundation

/// Something the user needs to know about, rather than a line in a log.
///
/// Hoot does its work in the background, so a failure that only reaches the
/// console is indistinguishable from the app doing nothing. Anything that
/// changes what Hoot can do for someone belongs here.
struct UserFacingIssue: Identifiable, Equatable {
    let id = UUID()
    let title: String
    /// What the user can actually do about it, when there is something.
    let suggestion: String?
    let occurredAt: Date
    let severity: Severity

    enum Severity {
        /// Hoot carried on with reduced ability.
        case warning
        /// Something the user asked for did not happen.
        case failure

        var symbolName: String {
            switch self {
            case .warning: return "exclamationmark.triangle"
            case .failure: return "xmark.octagon"
            }
        }
    }

    init(title: String, suggestion: String? = nil, severity: Severity = .failure) {
        self.title = title
        self.suggestion = suggestion
        self.occurredAt = Date()
        self.severity = severity
    }
}
