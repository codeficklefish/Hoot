import Foundation
import HootKit

/// When Hoot speaks up unprompted, and when it stays quiet.
///
/// These rules used to live as a field and two `if`s inside the app target,
/// which nothing here can import — so an app that interrupted twice about the
/// same pile, or announced the user's own downloads folder on first launch,
/// would have failed silently and only ever been caught by using it.
func stageAnnouncing(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[Hoot speaks up only when there is something new to say]")

    // ---- the opening sweep is not news ----
    let fresh = WaitingAnnouncer()
    check("files already in the folder are not announced",
          !fresh.shouldStartQuietPeriod(sweepInProgress: true))
    check("files arriving afterwards are",
          fresh.shouldStartQuietPeriod(sweepInProgress: false))

    // ---- growth is announced, exactly once ----
    var announcer = WaitingAnnouncer()
    let first = announcer.announcement(forPileOf: 3, topGroup: "Thesis")
    check("a pile that grew is announced", first?.count == 3, "\(first?.count ?? -1)")
    check("the announcement names the largest group",
          first?.topGroup == "Thesis", first?.topGroup ?? "nil")

    check("the same pile is not announced twice",
          announcer.announcement(forPileOf: 3, topGroup: "Thesis") == nil)

    let grown = announcer.announcement(forPileOf: 5, topGroup: "Thesis")
    check("further arrivals are announced, with the new total",
          grown?.count == 5, "\(grown?.count ?? -1)")

    // ---- a pile that shrank is not news ----
    check("a shrinking pile says nothing",
          announcer.announcement(forPileOf: 2, topGroup: "Thesis") == nil)
    check("and the earlier, larger total is still the baseline",
          announcer.announcement(forPileOf: 5, topGroup: "Thesis") == nil)

    // ---- organizing resets the baseline to what is left ----
    var afterOrganizing = WaitingAnnouncer()
    _ = afterOrganizing.announcement(forPileOf: 10, topGroup: nil)
    afterOrganizing.acknowledge(pileOf: 2)
    check("what is left after organizing is not re-announced",
          afterOrganizing.announcement(forPileOf: 2, topGroup: nil) == nil)
    check("growth beyond it is announced again",
          afterOrganizing.announcement(forPileOf: 3, topGroup: nil)?.count == 3)

    // ---- a different folder starts over ----
    var switched = WaitingAnnouncer()
    _ = switched.announcement(forPileOf: 8, topGroup: "Finance")
    switched.reset()
    check("a newly chosen folder is news even if it is smaller",
          switched.announcement(forPileOf: 1, topGroup: "Receipts")?.count == 1)

    // ---- the quiet period is long enough to be worth having ----
    // Extracting an archive can produce dozens of files in a second; the point
    // of the wait is that they arrive as one notification rather than dozens.
    check("the quiet period can coalesce a burst of arrivals",
          WaitingAnnouncer.quietPeriod >= .seconds(1),
          "\(WaitingAnnouncer.quietPeriod)")
}
