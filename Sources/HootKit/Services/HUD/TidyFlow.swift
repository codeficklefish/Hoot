import Foundation

/// One file inside a group the HUD is offering to file.
///
/// Carries both decisions at once — where it goes and what it is called —
/// because they are answered together. A file whose name says nothing is
/// usually also a file you cannot place by looking at it, so splitting the
/// two questions would mean asking about the same file twice.
public struct TidyFile: Equatable, Identifiable, Sendable {
    public let moveID: UUID
    public let currentName: String
    /// nil when Hoot was not confident enough to suggest one.
    public let proposedName: String?
    /// An SF Symbol name for the file's kind.
    public let kindSymbol: String
    /// When the file turned up in the watched folder. Only the tray uses it,
    /// to say how long something has been sitting there — which is the one
    /// thing that makes a pile feel like it needs answering.
    public let addedAt: Date?

    public var id: UUID { moveID }

    public init(
        moveID: UUID,
        currentName: String,
        proposedName: String?,
        kindSymbol: String,
        addedAt: Date? = nil
    ) {
        self.moveID = moveID
        self.currentName = currentName
        self.proposedName = proposedName
        self.kindSymbol = kindSymbol
        self.addedAt = addedAt
    }

    /// How long ago it arrived, in the fewest characters that still say it:
    /// "4m", "3h", "Yest.". Sits under a 44pt tile, so there is room for
    /// about five.
    public func ageLabel(now: Date = Date()) -> String? {
        guard let addedAt else { return nil }
        return Self.age(of: addedAt, now: now)
    }

    /// The same phrasing for a bare date, so the tray can describe its oldest
    /// file without having to hold on to which file that was.
    ///
    /// "Yest." is decided by the calendar rather than by elapsed hours. A file
    /// made at 23:30 on Sunday is 47 hours old at 22:30 on Tuesday, and
    /// calling that yesterday is simply wrong — the word names a day, so a day
    /// is what has to be counted.
    public static func age(of date: Date, now: Date = Date(),
                           calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0 else { return "now" }

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
        case ..<1:
            let minutes = Int(seconds / 60)
            if minutes < 1 { return "now" }
            if minutes < 60 { return "\(minutes)m" }
            return "\(minutes / 60)h"
        case 1:
            return "Yest."
        default:
            return "\(days)d"
        }
    }

    /// The clock time it arrived, for when an age cannot tell two files apart.
    /// Deliberately without a date: it is only ever shown for a set that
    /// already shares one.
    public static func arrivalTime(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// One destination folder, and why these files belong in it.
public struct TidyGroup: Equatable, Identifiable, Sendable {
    public let name: String
    public let reason: String
    public let files: [TidyFile]

    public var id: String { name }

    public init(name: String, reason: String, files: [TidyFile]) {
        self.name = name
        self.reason = reason
        self.files = files
    }
}

/// One file as the HUD draws it: which name is shown, which is struck out,
/// and what the line underneath says.
public struct TidyFileRow: Equatable, Identifiable, Sendable {
    public let file: TidyFile
    public let isKept: Bool
    /// The name this row leads with — the proposed one where there is one
    /// and renaming is on, otherwise the name the file already has.
    public let shownName: String
    /// The words before the struck-out name: "was", or why there is no new
    /// name to show.
    public let subLead: String
    /// The old name, struck through. nil when nothing is being replaced.
    public let replacedName: String?

    public var id: UUID { file.moveID }
}

/// What the HUD is showing.
public enum TidyStage: Equatable, Sendable {
    /// Nothing to file. The HUD does not appear at all.
    case idle
    /// A group waiting on a decision.
    case reviewing(TidyStep)
    /// Every group answered.
    case finished(TidySummary)
}

/// A group awaiting its decision, with everything the panel prints.
///
/// The labels live here rather than in the view so the suite can check them.
/// "Move & Rename 3" reading "Move & Rename 0" after the last file is
/// unticked is the kind of thing nobody notices until it ships.
public struct TidyStep: Equatable, Sendable {
    public let group: TidyGroup
    public let index: Int
    public let total: Int
    public let rows: [TidyFileRow]
    public let isRenaming: Bool
    /// Which folders have already been answered. The panel needs it to draw
    /// the run of pips: once you can move back and forth, "before the one
    /// showing" and "already dealt with" stop being the same thing.
    public let answered: Set<Int>

    /// Whether there is another unanswered folder to move to in each
    /// direction. What the swipe and the pips are allowed to do.
    public var hasNext: Bool { (index + 1..<total).contains { !answered.contains($0) } }
    public var hasPrevious: Bool { (0..<index).contains { !answered.contains($0) } }

    public var keptCount: Int { rows.filter(\.isKept).count }
    public var stepLabel: String { "\(index + 1) of \(total)" }
    public var pickedLabel: String { "\(keptCount)/\(group.files.count)" }

    /// The primary button. Says what will happen, counted, so nobody has to
    /// work out what "Apply" means here.
    public var primaryLabel: String {
        guard keptCount > 0 else { return "Nothing selected" }
        return isRenaming ? "Move & Rename \(keptCount)" : "Move \(keptCount)"
    }

    public var canApply: Bool { keptCount > 0 }

    /// The same count as `pickedLabel`, said in words rather than as a
    /// fraction. The notch layout puts it at the end of the folder's own
    /// line, where "2/3" reads as a date and "2 of 3 files" does not.
    public var pickedSentence: String {
        "\(keptCount) of \(group.files.count) \(group.files.count == 1 ? "file" : "files")"
    }

    /// The caption under the round action, which has room for two words.
    /// `primaryLabel` is the same decision spelled out, and stays as the
    /// button's tooltip — the count belongs somewhere, and under a 32pt
    /// circle is not that place.
    public var actionLabel: String {
        isRenaming ? "Move & name" : "Move"
    }

    /// Whether the panel's second column has anything to say: renaming is on,
    /// and at least one file in this folder has a name to move to.
    ///
    /// Not `renamableCount > 0`, which also asks whether the file is still
    /// ticked — a column that vanished when you unticked the one renamable
    /// file would move the other rows under the pointer. This asks only
    /// whether the column can ever say anything here, and when it cannot it
    /// prints the same sentence on every row, which is how a column stops
    /// being information and becomes furniture.
    public var showsProposedNames: Bool {
        isRenaming && rows.contains { $0.file.proposedName != nil }
    }

    /// Which of these files would actually be renamed — those kept, that
    /// have a name to move to, while renaming is on.
    public var renamableCount: Int {
        guard isRenaming else { return 0 }
        return rows.filter { $0.isKept && $0.file.proposedName != nil }.count
    }
}

/// What happened, once every group has been answered.
public struct TidySummary: Equatable, Sendable {
    public let movedFiles: Int
    public let movedGroups: Int
    public let renamedFiles: Int

    public init(movedFiles: Int, movedGroups: Int, renamedFiles: Int) {
        self.movedFiles = movedFiles
        self.movedGroups = movedGroups
        self.renamedFiles = renamedFiles
    }

    public var title: String {
        guard movedFiles > 0 else { return "Every file stayed where it was" }
        return "\(movedFiles) \(movedFiles == 1 ? "file" : "files") moved into "
            + "\(movedGroups) \(movedGroups == 1 ? "folder" : "folders")"
    }

    /// Always ends by saying it can be undone. This is the one screen where
    /// the user has just changed a lot of files at once, and safety rule 3
    /// is only reassuring if they know about it.
    public var detail: String {
        guard renamedFiles > 0 else {
            return "Nothing was renamed. Any move can be undone later."
        }
        return "\(renamedFiles) \(renamedFiles == 1 ? "file was" : "files were") "
            + "renamed too. Any move can be undone later."
    }
}

/// Filing a folder's worth of files at a time, from the notch.
///
/// One group per step, because a group is the unit a person can actually
/// judge: these files, this folder, this reason. The review window shows the
/// whole plan at once and is better at that; this is for answering the easy
/// ones without opening anything.
///
/// A value type with no opinions about drawing, so the suite drives the
/// whole flow — every label, every tally, every advance — without a screen.
public struct TidyFlow: Equatable, Sendable {
    public private(set) var groups: [TidyGroup]
    /// Which folder is showing. No longer a high-water mark: the walk can be
    /// moved back and forth, so this is a cursor rather than a count.
    public private(set) var step: Int
    /// The folders that have been answered — filed or left. Held separately
    /// from `step` for the same reason.
    private var answered: Set<Int>
    private var dropped: Set<UUID>
    /// Whether proposed names are applied along with the moves.
    public var isRenaming: Bool

    private var movedFiles = 0
    private var movedGroups = 0
    private var renamedFiles = 0

    /// Files the plan decided not to touch. Not part of the walk — there is
    /// nothing to answer about them — but the tray says how many there are,
    /// so that its count and the popover's add up to the same folder.
    public private(set) var leftAlone: Int

    public init(groups: [TidyGroup], isRenaming: Bool, leftAlone: Int = 0) {
        self.groups = groups
        self.step = 0
        self.answered = []
        self.dropped = []
        self.isRenaming = isRenaming
        self.leftAlone = leftAlone
    }

    /// Every file across every group, which is what the collapsed pill counts.
    public var totalFiles: Int { groups.reduce(0) { $0 + $1.files.count } }

    public var pillText: String {
        "\(totalFiles) \(totalFiles == 1 ? "file" : "files") could be sorted and named"
    }

    /// Everything still waiting on an answer.
    ///
    /// Counted from what has been answered rather than from where the cursor
    /// happens to be: now that the walk can be paged backwards, looking at an
    /// earlier folder must not make the pile appear to grow.
    public var pendingFiles: [TidyFile] {
        groups.enumerated()
            .filter { !answered.contains($0.offset) }
            .flatMap(\.element.files)
    }

    /// The folders those files would go to, counted.
    public var pendingGroupCount: Int { max(0, groups.count - answered.count) }

    /// What the collapsed bar says when it is wide enough to say anything.
    /// Two words, because on a notched Mac this is read in the gap either
    /// side of a camera housing.
    public var pillCount: String {
        pendingFiles.isEmpty ? "Idle" : "\(pendingFiles.count) new"
    }

    /// The tray's headline.
    public var waitingTitle: String {
        let count = pendingFiles.count
        return "\(count) \(count == 1 ? "file" : "files") waiting"
    }

    /// The line under it: how many folders that is, and how long the oldest
    /// of them has been sitting there.
    public func waitingDetail(now: Date = Date()) -> String {
        let folders = pendingGroupCount
        var parts = ["\(folders) \(folders == 1 ? "folder" : "folders") suggested"]
        if let oldest = pendingFiles.compactMap(\.addedAt).min()
            .map({ TidyFile.age(of: $0, now: now) }) {
            parts.append("oldest \(oldest)")
        }
        // Said here as well as in the popover. A count that appears on one
        // surface and not the other is how two views of one folder start to
        // disagree about it.
        if leftAlone > 0 { parts.append("\(leftAlone) left alone") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// What to print under each tile in the tray.
    ///
    /// An age is the most useful caption right up until every file has the
    /// same one — a folder filled in a single evening reads as five tiles
    /// saying "Yest.", which is true and says nothing about which tile is
    /// which. Then the whole row falls back to clock times, which differ.
    /// Decided across the set rather than per file, because "do these tell
    /// them apart" is a question about the set.
    public func trayCaptions(now: Date = Date()) -> [UUID: String] {
        let dated = pendingFiles.compactMap { file in
            file.addedAt.map { (file.moveID, $0) }
        }
        guard !dated.isEmpty else { return [:] }

        let ages = dated.map { ($0.0, TidyFile.age(of: $0.1, now: now)) }
        guard Set(ages.map(\.1)).count == 1, dated.count > 1 else {
            return Dictionary(uniqueKeysWithValues: ages)
        }
        return Dictionary(uniqueKeysWithValues: dated.map { ($0.0, TidyFile.arrivalTime(of: $0.1)) })
    }

    public var stage: TidyStage {
        guard !groups.isEmpty else { return .idle }
        // Finished when every folder has been answered, not when the cursor
        // has run off the end — it can no longer do that, and a walk with one
        // folder still unanswered behind you is not finished.
        guard answered.count < groups.count else {
            return .finished(TidySummary(
                movedFiles: movedFiles, movedGroups: movedGroups, renamedFiles: renamedFiles
            ))
        }
        return .reviewing(currentStep)
    }

    private var currentStep: TidyStep {
        let group = groups[step]
        return TidyStep(
            group: group,
            index: step,
            total: groups.count,
            rows: group.files.map(row(for:)),
            isRenaming: isRenaming,
            answered: answered
        )
    }

    private func row(for file: TidyFile) -> TidyFileRow {
        let willRename = isRenaming && file.proposedName != nil
        return TidyFileRow(
            file: file,
            isKept: !dropped.contains(file.moveID),
            shownName: willRename ? (file.proposedName ?? file.currentName) : file.currentName,
            subLead: willRename ? "was"
                : file.proposedName != nil ? "keeps its name"
                    : "no clear name to suggest",
            replacedName: willRename ? file.currentName : nil
        )
    }

    /// The files this step would actually act on.
    public var keptFiles: [TidyFile] {
        guard step < groups.count else { return [] }
        return groups[step].files.filter { !dropped.contains($0.moveID) }
    }

    // MARK: - Answering

    public mutating func toggle(_ fileID: UUID) {
        if dropped.contains(fileID) { dropped.remove(fileID) } else { dropped.insert(fileID) }
    }

    /// Records that this group's kept files were filed, and moves on.
    ///
    /// Takes the counts rather than deriving them: what actually landed on
    /// disk is what the organizer managed, not what was asked for, and the
    /// summary must not claim more than happened.
    public mutating func recordApplied(movedFiles moved: Int, renamedFiles renamed: Int) {
        movedFiles += moved
        if moved > 0 { movedGroups += 1 }
        renamedFiles += renamed
        settle()
    }

    /// Leaves this group where it is and moves on.
    public mutating func skip() { settle() }

    /// Marks the folder showing as answered and moves to one that is not.
    ///
    /// Forwards first, then round to the beginning: a folder skipped past
    /// earlier is still waiting, and the walk should end having asked about
    /// every one of them rather than quietly dropping the ones behind.
    private mutating func settle() {
        answered.insert(step)
        if let next = firstUnanswered(from: step + 1) ?? firstUnanswered(from: 0) {
            step = next
        }
    }

    // MARK: - Moving between folders
    //
    // Answering is not the only way through. A pile is easier to judge when
    // you can look at what else is in it first, so the panel can be paged —
    // by swipe, or by clicking a pip — without that counting as a decision.

    public var canShowNext: Bool { firstUnanswered(from: step + 1) != nil }
    public var canShowPrevious: Bool { lastUnanswered(before: step) != nil }

    public mutating func showNext() {
        if let next = firstUnanswered(from: step + 1) { step = next }
    }

    public mutating func showPrevious() {
        if let previous = lastUnanswered(before: step) { step = previous }
    }

    /// Jumps straight to one folder. Ignores a folder already answered and
    /// anything outside the walk, so a stray tap cannot strand the panel on a
    /// group it has nothing to show for.
    public mutating func show(groupAt index: Int) {
        guard groups.indices.contains(index), !answered.contains(index) else { return }
        step = index
    }

    private func firstUnanswered(from start: Int) -> Int? {
        guard start < groups.count else { return nil }
        return (max(0, start)..<groups.count).first { !answered.contains($0) }
    }

    private func lastUnanswered(before end: Int) -> Int? {
        guard end > 0 else { return nil }
        return (0..<min(end, groups.count)).last { !answered.contains($0) }
    }

    /// Back to the first group with every tally cleared, for Undo.
    public mutating func restart() {
        step = 0
        answered = []
        dropped = []
        movedFiles = 0
        movedGroups = 0
        renamedFiles = 0
    }
}
