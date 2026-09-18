import Foundation

/// The folders the user chose, as the notch shows them.
///
/// A plain value with no opinions about drawing, for the same reason
/// `TidyFlow` was one: every label, every count and every cap is then
/// something the suite can assert without a screen in front of it. The
/// surface this replaces was written the other way round once, and the app
/// crash-looped all evening while the checks passed.
public struct FileShelf: Equatable, Sendable {

    /// As many folders as the tab row can *name*.
    ///
    /// Three, because the constraint is legibility rather than storage. The
    /// row has about 280 points once the add control and the file count have
    /// taken theirs, and three ordinary folder names fit in that at full
    /// size. At eight they were being squeezed to "Des…", "Docu…", "Dow…" —
    /// a tab you cannot read is not a tab, it is a guess.
    public static let maxFolders = 3
    /// Rows before the list starts scrolling rather than the window growing.
    public static let maxRows = 9
    public static let rowHeight: Double = 26

    /// How long the pointer has to rest on a tab before the panel changes
    /// folder under it.
    ///
    /// Not zero, and the reason is the gap between the tabs and the `+`
    /// beside them: reaching for that control means crossing every tab on the
    /// way, and a shelf that switched on contact would read three folders off
    /// the disk and throw away the picked row to do it. Long enough to tell
    /// crossing from pointing, short enough that pointing does not feel like
    /// waiting — roughly the dwell a menu bar uses to open a sibling menu.
    public static let hoverDwell: TimeInterval = 0.18

    /// How many folders deep the list will open in place.
    ///
    /// Four, because each level costs indentation out of a 420pt panel and
    /// the names have to stay readable — the same constraint that caps the
    /// tabs at three. Past it a folder is somewhere to *go* rather than
    /// something to open where you stand, and the panel says so.
    public static let maxDepth = 4

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

    /// Folders opened in place, by path, and what was read for each.
    ///
    /// Two collections rather than one, because they answer different
    /// questions and go stale at different rates: `open` is what the person
    /// asked for and survives a re-read, `opened` is what was on the disk
    /// last time anyone looked and is replaced wholesale by one.
    public private(set) var open: Set<String> = []
    private var opened: [String: ShelfFolder] = [:]

    public init(folders: [ShelfFolder] = [], showing: Int = 0,
                sort: SortOrder = .added, selected: String? = nil) {
        self.folders = folders
        self.showing = folders.isEmpty ? 0 : min(max(showing, 0), folders.count - 1)
        self.sort = sort
        self.selected = selected
    }

    // MARK: - What is on screen

    public var isEmpty: Bool { folders.isEmpty }

    /// Whether another folder will fit. The `+` is shown either way and
    /// disabled when it will not, rather than vanishing — a control that
    /// disappears leaves you wondering where it went.
    public var hasRoom: Bool { folders.count < Self.maxFolders }

    public var current: ShelfFolder? {
        guard folders.indices.contains(showing) else { return nil }
        return folders[showing]
    }

    /// The collapsed bar names the folder rather than counting anything.
    /// A count there would be a third number beside the popover's chips and
    /// the review window's header, and those two disagreeing once was enough.
    public var pillText: String { current?.listingName ?? "Hoot" }

    public var title: String { current?.listingName ?? "No folders yet" }
    public var accessory: String { current?.accessory ?? "" }

    public var emptyMessage: String {
        guard let current else {
            return "No folders yet — use + to add one."
        }
        return current.emptyMessage
    }

    /// The folder's rows in the chosen order, folders first, with any folder
    /// opened in place followed by what is inside it.
    ///
    /// Folders lead however the rest is sorted, which is what the Finder does
    /// and therefore what the eye expects — a folder sorted into the middle
    /// of a file list by size reads as a mistake. The same order applies at
    /// every level, so a folder opened in place is sorted like the list it is
    /// sitting in rather than like a separate thing.
    public var rows: [ShelfRowItem] {
        guard let current else { return [] }
        return flatten(current.ordered(by: sort), depth: 0)
    }

    private func flatten(_ entries: [ShelfEntry], depth: Int) -> [ShelfRowItem] {
        var out: [ShelfRowItem] = []
        for entry in entries {
            let isOpen = open.contains(entry.key)
            out.append(
                ShelfRowItem(
                    entry: entry,
                    depth: depth,
                    // A folder in the cloud that is not downloaded gets no
                    // triangle: there is nothing to show without fetching it,
                    // and safety rule 5 says Hoot does not.
                    disclosure: entry.isEnterable ? (isOpen ? .open : .closed) : .plain
                )
            )
            guard isOpen, let inside = opened[entry.key] else { continue }
            out += flatten(inside.ordered(by: sort), depth: depth + 1)
        }
        return out
    }

    /// A definite height, so the window stops growing where the list starts
    /// scrolling. See `HUDPlacement.listHeight`.
    public var listHeight: Double {
        HUDPlacement.listHeight(rows: rows.count,
                                rowHeight: Self.rowHeight,
                                maxRows: Self.maxRows)
    }

    // MARK: - The footer

    public var pickedRow: ShelfRowItem? {
        guard let selected else { return nil }
        return rows.first { $0.id == selected }
    }

    public var pickedEntry: ShelfEntry? { pickedRow?.entry }

    public func selectionDetail(now: Date = Date(), calendar: Calendar = .current) -> String? {
        pickedEntry?.detail(now: now, calendar: calendar)
    }

    /// What the reveal button offers. With nothing picked there is still
    /// something useful to do — open the folder itself.
    public var revealLabel: String {
        pickedEntry == nil ? "Open folder" : "Show in Finder"
    }

    /// What the panel says after handing something to the Finder.
    ///
    /// Phrased here rather than at the call site for the same reason every
    /// other label on this type is: a sentence with a count in it is exactly
    /// the kind of thing that reads "1 files" in the one case nobody tried.
    public var revealMessage: String {
        if let picked = pickedEntry { return "Revealed \(picked.name) in the Finder" }
        return "Opened \(title) in the Finder"
    }

    /// And after sending the watched folder to the review window.
    public func tidyMessage(untidy: Int) -> String {
        "Review opened — \(untidy) \(untidy == 1 ? "file" : "files") in \(title) to sort and name"
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

    /// Takes a tab off the shelf. Matched on the root, because `url` may be
    /// somewhere inside the folder by the time anyone asks — and on identity
    /// rather than on the string, for the trailing-slash and symlink reasons
    /// `FolderIdentity` exists to record.
    public mutating func remove(_ url: URL) {
        guard let index = folders.firstIndex(where: { FolderIdentity.same($0.root, url) })
        else { return }
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

    /// Whether pointing at this tab should change what the panel lists.
    ///
    /// Asked before the work rather than after it, because the tab already
    /// showing is the one the pointer crosses most — on its way along the row
    /// to the `+`, or back to the list. Answering "no" for that one is what
    /// keeps a passing cursor from re-reading the folder off the disk and
    /// dropping whichever row was picked.
    public func shouldShow(folderAt index: Int) -> Bool {
        folders.indices.contains(index) && index != showing
    }

    public mutating func show(folderAt index: Int) {
        guard shouldShow(folderAt: index) else { return }
        showing = index
        // The open folders were rows in the list you are leaving.
        collapseAll()
        // A different folder cannot have the picked row in it, so the
        // selection goes with it. Staying on the same folder keeps it: that
        // is now a no-op above, and it has to be, or pointing at the tab you
        // are already on would put down the row you just picked.
        selected = nil
    }

    public mutating func showNext() { show(folderAt: showing + 1) }
    public mutating func showPrevious() { show(folderAt: showing - 1) }

    /// Sets the selection rather than toggling it.
    ///
    /// Toggling reads well until a double-click arrives: the two clicks would
    /// select and then deselect on their way to opening the file, and the row
    /// would flicker out from under the pointer. It is also what the Finder
    /// does — clicking a selected row there leaves it selected. Escape is
    /// what puts a row down.
    public mutating func select(_ id: String?) {
        selected = id
    }

    public mutating func deselect() {
        selected = nil
    }

    // MARK: - Opening a folder where it stands

    public var hasOpenFolders: Bool { !open.isEmpty }

    /// Whether this row may be opened in place, rather than only entered.
    public func canOpen(_ row: ShelfRowItem) -> Bool {
        row.isEnterable && row.depth + 1 < Self.maxDepth
    }

    /// The paths to re-read, as paths that can be opened again.
    public var openFolders: [URL] { open.map { URL(fileURLWithPath: $0) } }

    /// What the panel says when a row is too deep to open where it stands.
    public func tooDeepMessage(_ row: ShelfRowItem) -> String {
        "\(row.name) is as deep as the list goes — double-click to go into it."
    }

    /// Keyed on identity rather than on the URL as written. Two spellings of
    /// one path would otherwise be two different folders, and a folder closed
    /// under one spelling would stay open under the other.
    public mutating func open(_ url: URL, showing folder: ShelfFolder) {
        let key = FolderIdentity.key(url)
        open.insert(key)
        opened[key] = folder
    }

    /// Closes a folder, and everything that was open inside it.
    ///
    /// The descendants matter: leaving them in `open` would mean re-opening
    /// this folder silently re-opened three more, and leaving them in
    /// `opened` would mean it re-opened them showing whatever was there
    /// minutes ago.
    public mutating func close(_ url: URL) {
        let id = FolderIdentity.key(url)
        let inside = id.hasSuffix("/") ? id : id + "/"
        for path in open where path == id || path.hasPrefix(inside) {
            open.remove(path)
            opened[path] = nil
        }
    }

    public mutating func collapseAll() {
        open.removeAll()
        opened.removeAll()
    }

    /// Swaps in freshly read contents for the folders still open.
    ///
    /// Keyed rather than wholesale, and it drops anything no longer open, so
    /// a re-read that lands after somebody closed a folder cannot re-open it.
    public mutating func refreshOpen(_ reads: [String: ShelfFolder]) {
        for (id, folder) in reads where open.contains(id) {
            opened[id] = folder
        }
    }
}
