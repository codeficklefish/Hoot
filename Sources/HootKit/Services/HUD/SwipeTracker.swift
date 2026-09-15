import Foundation

/// Turns a stream of trackpad deltas into at most one page turn.
///
/// In the engine, and a value type, for the same reason `HUDPlacement` is:
/// the interesting part is arithmetic — how far is far enough, which axis
/// wins, how many folders one flick may cross — and arithmetic that can be
/// checked should be checked. The app target only has to hand it the numbers
/// AppKit already provides.
public struct SwipeTracker: Equatable, Sendable {

    /// Where the gesture is in its life. A trackpad reports these; a mouse
    /// wheel reports nothing, which is why `changed` is the default.
    public enum Phase: Sendable {
        case began, changed, ended
    }

    public enum Direction: Equatable, Sendable {
        case previous, next
    }

    /// How far a flick must travel before it counts. Short enough to feel
    /// like a flick rather than a drag, long enough that the sideways drift
    /// in an ordinary two-finger scroll never reaches it.
    public static let threshold: Double = 28

    /// A gesture more vertical than horizontal is somebody scrolling, not
    /// paging. Requiring the horizontal part to lead by this much keeps a
    /// slightly crooked scroll from turning the page under them.
    public static let axisBias: Double = 1.4

    private var travel: Double = 0
    private var hasFired = false

    public init() {}

    /// Feeds one event in and returns a direction the moment the gesture has
    /// earned one — once per gesture, however far it carries on afterwards.
    /// A flick is one page turn; crossing four folders in a single swipe
    /// would leave nobody able to say which one they had landed on.
    public mutating func track(deltaX: Double, deltaY: Double, phase: Phase) -> Direction? {
        if phase == .began {
            travel = 0
            hasFired = false
        }
        defer {
            if phase == .ended {
                travel = 0
                hasFired = false
            }
        }

        guard abs(deltaX) > abs(deltaY) * Self.axisBias else { return nil }
        travel += deltaX
        guard !hasFired, abs(travel) >= Self.threshold else { return nil }
        hasFired = true

        // Fingers left moves the panel's contents left, which brings the next
        // folder in from the right — the direction every pageable surface on
        // the Mac already uses.
        return travel < 0 ? .next : .previous
    }
}
