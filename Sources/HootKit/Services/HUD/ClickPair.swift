import Foundation

/// Telling the second click of a pair from the first, without waiting to find
/// out which it was.
///
/// SwiftUI separates them with `onTapGesture(count: 2)` declared before
/// `onTapGesture(count: 1)`, and that does work — but the single tap cannot
/// fire until the double-click interval has passed with no second click
/// arriving. That is a quarter of a second between clicking a row and the row
/// looking clicked, on a surface whose whole promise is that it answers while
/// you are still pointing at it.
///
/// Removing the wait by making the single tap a `simultaneousGesture` removes
/// the double-click with it: it wins the arbitration on the first click, so
/// `count: 2` never fires at all. That was tried, and the report was "the
/// double click isn't working".
///
/// So the row keeps one tap gesture, which fires at once, and the *pairing*
/// happens here: a click on the same row soon enough after the last one is
/// the second of a pair. Nothing is ever delayed, because nothing is waiting
/// to see whether a first click was going to become a second.
///
/// The interval is passed in rather than fixed. It is a system preference —
/// `NSEvent.doubleClickInterval`, which the person sets in System Settings —
/// and a surface that picked its own number would be slower or faster than
/// every other double-click on their Mac.
public struct ClickPair: Equatable, Sendable {
    public init() {}

    private var lastRow: String?
    private var lastClick: Date?

    /// Records a click and answers whether it completed a pair.
    ///
    /// The same row, and soon enough. Two quick clicks on *different* rows are
    /// two first clicks rather than a double-click — which is what the Finder
    /// does, and what anyone picking their way down a list needs.
    public mutating func isSecond(
        _ id: String,
        at now: Date,
        within interval: TimeInterval
    ) -> Bool {
        let paired = lastRow == id && lastClick.map { last in
            let gap = now.timeIntervalSince(last)
            // Not merely `<= interval`: a clock that went backwards gives a
            // negative gap, which would pair two clicks an hour apart.
            return gap >= 0 && gap <= interval
        } == true

        if paired {
            // A completed pair starts over. Without this a third click inside
            // the interval would pair with the second, and a rapid triple
            // click would open the row twice.
            lastRow = nil
            lastClick = nil
        } else {
            lastRow = id
            lastClick = now
        }

        return paired
    }
}
