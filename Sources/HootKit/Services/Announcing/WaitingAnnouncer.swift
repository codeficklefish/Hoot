import Foundation

/// What Hoot has decided to say about files waiting for review.
public struct Announcement: Equatable {
    public let count: Int
    /// The largest group in the pile, so the notification can say what the
    /// files look like rather than only how many there are.
    public let topGroup: String?

    public init(count: Int, topGroup: String?) {
        self.count = count
        self.topGroup = topGroup
    }
}

/// Decides when Hoot speaks up unprompted, and — mostly — when it doesn't.
///
/// Hoot lives in the menu bar and can go unlooked-at for days, so a
/// notification is the only way it can say "there is something here". That
/// makes restraint the whole design: an app that interrupts twice for the same
/// pile is one the user turns off.
///
/// Three rules, and they are the reason this is a module rather than an `if`
/// at the call site. The count they are all about was previously a field on
/// the app's state, written from three different files, which is precisely how
/// a rule like "don't say the same thing twice" stops holding.
public struct WaitingAnnouncer {

    /// How long the folder must stop changing before anything is said.
    ///
    /// Unzipping an archive can produce dozens of files in a second, and each
    /// one should not be its own notification. The caller waits this out,
    /// restarting the clock on every arrival.
    public static let quietPeriod = Duration.seconds(4)

    /// The size of the pile the last time Hoot said something about it.
    private var lastAnnouncedCount = 0

    public init() {}

    /// Whether a change to the folder should start the quiet period at all.
    ///
    /// Files already sitting in the folder when Hoot was pointed at it are not
    /// news — the user put them there, and being told about their own
    /// downloads folder on first launch reads as a malfunction. Only what
    /// arrives after the opening sweep is worth announcing.
    public func shouldStartQuietPeriod(sweepInProgress: Bool) -> Bool {
        !sweepInProgress
    }

    /// What to say now that the folder has settled, or nil to stay quiet.
    ///
    /// Only growth is news. A pile that shrank because the user organized some
    /// of it, or held steady because nothing arrived, has nothing to report —
    /// so this speaks up only when there is more than there was last time, and
    /// then remembers the new total.
    public mutating func announcement(forPileOf count: Int, topGroup: String?) -> Announcement? {
        guard count > lastAnnouncedCount else { return nil }
        lastAnnouncedCount = count
        return Announcement(count: count, topGroup: topGroup)
    }

    /// Records that the user has dealt with the pile, so what is left becomes
    /// the new baseline rather than counting as growth next time.
    public mutating func acknowledge(pileOf count: Int) {
        lastAnnouncedCount = count
    }

    /// A different folder entirely: nothing has been said about this one.
    public mutating func reset() {
        lastAnnouncedCount = 0
    }
}
