import Foundation

/// The folders the user chose, as the notch shows them.
///
/// A plain value with no opinions about drawing, for the same reason
/// `TidyFlow` was one: every label, every count and every cap is then
/// something the suite can assert without a screen in front of it. The
/// surface this replaces was written the other way round once, and the app
/// crash-looped all evening while the checks passed.
public struct FileShelf: Equatable, Sendable {

    /// As many folders as the tab row can name without turning into a menu.
    /// A product call, not a derivation.
    public static let maxFolders = 8
    /// Rows before the list starts scrolling rather than the window growing.
    public static let maxRows = 9
    public static let rowHeight: Double = 26

    /// The orders a folder can be read in. Cycled by one control rather than
    /// chosen from a menu: three is few enough to arrive at by pressing.
    public enum SortOrder: String, CaseIterable, Sendable {
        case added, name, size

        public var label: String {
            switch self {
            case .added: return "Date added"
            case .name: return "Name"
            case .size: return "Size"
            }
        }

        public var next: SortOrder {
            let all = SortOrder.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    public private(set) var folders: [ShelfFolder]
    public private(set) var showing: Int
    public var sort: SortOrder
    /// The picked row, by `ShelfEntry.id`. Held here rather than in the view
    /// because the panel's root view is replaced on every refresh, and state
    /// living in the view would not survive it.
    public private(set) var selected: String?

    public init(folders: [ShelfFolder] = [], showing: Int = 0,
                sort: SortOrder = .added, selected: String? = nil) {
        self.folders = folders
        self.showing = folders.isEmpty ? 0 : min(max(showing, 0), folders.count - 1)
        self.sort = sort
        self.selected = selected
    }

    // MARK: - What is on screen

    public var isEmpty: Bool { folders.isEmpty }

    public var current: ShelfFolder? {
        guard folders.indices.contains(showing) else { return nil }
        return folders[showing]
    }

    /// The collapsed bar names the folder rather than counting anything.
    /// A count there would be a third number beside the popover's chips and
    /// the review window's header, and those two disagreeing once was enough.
    public var pillText: String { current?.name ?? "Hoot" }

    public var title: String { current?.name ?? "No folders yet" }
    public var accessory: String { current?.accessory ?? "" }

    public var emptyMessage: String {
        guard let current else {
            return "Add a folder in Settings and it will be here."
        }
        return current.emptyMessage
    }

    /// The folder's rows in the chosen order, folders first.
    ///
    /// Folders lead however the rest is sorted, which is what the Finder does
    /// and therefore what the eye expects — a folder sorted into the middle
    /// of a file list by size reads as a mistake.
    public var rows: [ShelfEntry] {
        guard let entries = current?.entries else { return [] }
        let ordered = entries.sorted { left, right in
            switch sort {
            case .added:
                // Newest first. A file with no date sits at the bottom rather
                // than claiming to be the oldest thing there.
                switch (left.sortDate, right.sortDate) {
                case let (l?, r?): return l > r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return left.name < right.name
                }
            case .name:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .size:
                return left.byteCount > right.byteCount
            }
        }
        // Partitioned rather than sorted a second time. Swift's `sorted(by:)`
        // is not stable, so a folders-first comparison pass would be free to
        // scramble the order just established within each group.
        return ordered.filter(\.isFolder) + ordered.filter { !$0.isFolder }
    }

    /// A definite height, so the window stops growing where the list starts
    /// scrolling. See `HUDPlacement.listHeight`.
    public var listHeight: Double {
        HUDPlacement.listHeight(rows: rows.count,
                                rowHeight: Self.rowHeight,
                                maxRows: Self.maxRows)
    }

    // MARK: - The footer

    public var pickedEntry: ShelfEntry? {
        guard let selected else { return nil }
        return rows.first { $0.id == selected }
    }

    public func selectionDetail(now: Date = Date(), calendar: Calendar = .current) -> String? {
        pickedEntry?.detail(now: now, calendar: calendar)
    }

    /// What the reveal button offers. With nothing picked there is still
    /// something useful to do — open the folder itself.
    public var revealLabel: String {
        pickedEntry == nil ? "Open folder" : "Show in Finder"
    }

    /// The one place the organizer surfaces here, and only for a folder that
    /// has a plan — which is the watched folder and no other. Nil hides the
    /// button rather than showing a zero.
    public func tidyLabel(untidy: Int) -> String? {
        untidy > 0 ? "Tidy \(untidy)" : nil
    }

    // MARK: - Changing it

    /// False when the folder is already here or there is no room. The cap
    /// lives in this value rather than in the adapter that stores bookmarks,
    /// so that it is a rule with a check rather than a constant on a class.
    @discardableResult
    public mutating func add(_ folder: ShelfFolder) -> Bool {
        guard folders.count < Self.maxFolders else { return false }
        guard !folders.contains(where: { $0.id == folder.id }) else { return false }
        folders.append(folder)
        return true
    }

    public mutating func remove(_ url: URL) {
        guard let index = folders.firstIndex(where: { $0.url.path == url.path }) else { return }
        folders.remove(at: index)
        // Whatever is showing must still exist. Clamping rather than resetting
        // to zero, so removing the last tab leaves you on the one before it
        // instead of jumping to the front.
        showing = folders.isEmpty ? 0 : min(showing, folders.count - 1)
        selected = nil
    }

    /// Swaps in a freshly read folder, leaving the cursor and the selection
    /// alone. Re-reading an unchanged folder produces an equal value, so this
    /// is a no-op the panel can afford to do on every open.
    public mutating func replace(_ folder: ShelfFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index] = folder
    }

    public mutating func show(folderAt index: Int) {
        guard folders.indices.contains(index) else { return }
        showing = index
        selected = nil
    }

    public mutating func showNext() { show(folderAt: showing + 1) }
    public mutating func showPrevious() { show(folderAt: showing - 1) }

    /// Picking the picked row unpicks it, so a click is always reversible by
    /// the same click.
    public mutating func select(_ id: String?) {
        selected = (selected == id) ? nil : id
    }
}
