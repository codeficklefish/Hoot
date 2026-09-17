import Foundation

/// How long ago something arrived, said in as few characters as will do.
///
/// Extracted from `TidyFile`, which is being replaced. The rules are worth
/// keeping intact rather than rewriting beside the surface that needs them
/// next: the calendar arithmetic below was got wrong once already, and the
/// comment explaining why is the whole value of the file.
public enum RelativeAge {

    /// The compact form, for a column: "4m", "3h", "Yest.", "2d".
    ///
    /// "Yest." is decided by the calendar rather than by elapsed hours. A file
    /// made at 23:30 on Sunday is 47 hours old at 22:30 on Tuesday, and
    /// calling that yesterday is simply wrong — the word names a day, so a day
    /// is what has to be counted.
    public static func label(of date: Date, now: Date = Date(),
                             calendar: Calendar = .current) -> String {
        switch elapsed(from: date, to: now, calendar: calendar) {
        case .ahead: return "now"
        case .today(let minutes):
            if minutes < 1 { return "now" }
            if minutes < 60 { return "\(minutes)m" }
            return "\(minutes / 60)h"
        case .yesterday: return "Yest."
        case .days(let days): return "\(days)d"
        }
    }

    /// The spoken form, for a sentence: "4m ago", "3h ago", "yesterday".
    ///
    /// Separate from `label` rather than derived from it. "Yest. ago" is not
    /// English, and a footer that reads "1d ago" where a person would say
    /// "yesterday" is the kind of small wrongness nobody reports and everybody
    /// notices.
    public static func since(_ date: Date, now: Date = Date(),
                             calendar: Calendar = .current) -> String {
        switch elapsed(from: date, to: now, calendar: calendar) {
        case .ahead: return "just now"
        case .today(let minutes):
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes)m ago" }
            return "\(minutes / 60)h ago"
        case .yesterday: return "yesterday"
        case .days(let days): return "\(days)d ago"
        }
    }

    /// The clock time it arrived, for when an age cannot tell two files apart.
    /// Deliberately without a date: it is only ever shown for a set that
    /// already shares one.
    public static func clockTime(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: - The one piece of arithmetic both forms share

    private enum Elapsed {
        case ahead
        case today(minutes: Int)
        case yesterday
        case days(Int)
    }

    private static func elapsed(from date: Date, to now: Date,
                                calendar: Calendar) -> Elapsed {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0 else { return .ahead }

        // Counted between the two days themselves, not with
        // `isDateInYesterday`, which answers against the system clock rather
        // than the `now` it was handed — so the suite could not pin it down,
        // and an hour either side of midnight it disagreed with itself.
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<1: return .today(minutes: Int(seconds / 60))
        case 1: return .yesterday
        default: return .days(days)
        }
    }
}
