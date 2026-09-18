import Foundation

/// One line of a folder, as the notch prints it.
///
/// Built from a `FileItem` rather than being one. `FileItem` takes a fresh
/// `UUID` every time it is constructed, so re-reading an unchanged folder
/// would produce values that compare unequal — and the panel would redraw
/// under the pointer every few seconds for no reason. Identity here is the
/// path, which is what the folder actually means by "the same file".
public struct ShelfEntry: Equatable, Identifiable, Sendable {
    public init(
        url: URL,
        symbolName: String,
        isFolder: Bool,
        byteCount: Int64,
        childCount: Int,
        sortDate: Date?,
        isCloudPlaceholder: Bool
    ) {
        self.url = url
        // Resolved once, here, where a disk is being touched anyway. It is
        // used on every draw to decide which folders are open, and
        // `resolvingSymlinksInPath` is a syscall — doing it per row per frame
        // would put the file system in the middle of the render loop.
        self.key = FolderIdentity.key(url)
        self.symbolName = symbolName
        self.isFolder = isFolder
        self.byteCount = byteCount
        self.childCount = childCount
        self.sortDate = sortDate
        self.isCloudPlaceholder = isCloudPlaceholder
    }

    public let url: URL
    /// The one spelling of this row's path that everything can agree on.
    ///
    /// `/tmp` is a symlink to `/private/tmp`, so a path built by hand and the
    /// same path read off the disk are different strings for the same file.
    /// A check caught this: closing a folder failed to close what was open
    /// inside it, because one path said `/var/...` and the other
    /// `/private/var/...`. See `FolderIdentity`.
    public let key: String
    public let symbolName: String
    public let isFolder: Bool
    /// Meaningless for a folder, which is measured in things rather than bytes.
    public let byteCount: Int64
    public let childCount: Int
    /// When it arrived. Created rather than modified: a download that was
    /// edited after it landed has not been waiting any less long.
    public let sortDate: Date?
    /// Stored in the cloud and not downloaded. Safety rule 5 says it is never
    /// opened, and this is that rule reaching a surface that is not the
    /// organizer — previewing one would start a download nobody asked for.
    public let isCloudPlaceholder: Bool

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    /// Whether anything at all may open this row.
    ///
    /// False only for a file that is in the cloud and not downloaded. Safety
    /// rule 5 reaching a surface that is not the organizer: previewing it,
    /// opening it or handing it to another app would each start a download
    /// nobody asked for. A rule rather than a `guard` in the view, so that
    /// every gesture asks the same question and the suite can check it.
    public var isOpenable: Bool { !isCloudPlaceholder }

    /// Quick Look, the panel the Finder opens on space.
    ///
    /// Not for a folder. Quick Look shows one an icon and a count, which is
    /// what the row already says — so the shelf lists its contents instead.
    public var isPreviewable: Bool { isOpenable && !isFolder }

    /// Somewhere to go rather than something to look at.
    public var isEnterable: Bool { isOpenable && isFolder }

    /// The size column. A folder is counted, not measured — "6 items" is
    /// what the Finder says and what someone glancing at a row expects.
    public var sizeLabel: String {
        guard !isFolder else {
            return childCount == 1 ? "1 item" : "\(childCount) items"
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// The age column: "4m", "3h", "Yest.".
    public func ageLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let sortDate else { return "" }
        return RelativeAge.label(of: sortDate, now: now, calendar: calendar)
    }

    /// The sentence the footer prints once a row is picked. A folder is not
    /// "added", it is simply there, so the two read differently.
    public func detail(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let sortDate else { return sizeLabel }
        let ago = RelativeAge.since(sortDate, now: now, calendar: calendar)
        return isFolder ? "\(sizeLabel) · \(ago)" : "\(sizeLabel) · added \(ago)"
    }
}

/// One folder on the shelf, and whether it could be read.
///
/// Two URLs, because a tab and a listing stopped being the same thing when
/// folder rows became somewhere to go. `root` is what the user put on the
/// shelf and what the sandbox granted; `url` is the directory on screen,
/// which is `root` or somewhere under it. Identity is the root, so a tab
/// keeps its place, its name and its bookmark however deep you are in it.
public struct ShelfFolder: Equatable, Identifiable, Sendable {
    /// Why a folder might have no rows. Told apart on purpose: an empty
    /// Downloads folder is good news, and a folder on an ejected disk is not,
    /// and printing the same line for both would be a small lie.
    public enum State: Equatable, Sendable {
        case listed, empty, unavailable
    }

    public init(root: URL, url: URL? = nil, state: State, entries: [ShelfEntry]) {
        self.root = root
        self.url = url ?? root
        self.state = state
        self.entries = entries
    }

    /// The tab: the folder that was added, and the only one that was granted.
    public let root: URL
    /// The directory being listed, at or below `root`.
    public let url: URL
    public let state: State
    public let entries: [ShelfEntry]

    public var id: String { root.path }
    /// The tab's label, which never changes as you go down.
    public var name: String { root.lastPathComponent }
    /// What is actually on screen, which does.
    public var listingName: String { url.lastPathComponent }

    /// The way down from the tab to what is listed, tab excluded.
    ///
    /// Computed from the two paths rather than carried as a stack, so it
    /// cannot disagree with the folder that was read. A `url` that is not
    /// under `root` gives an empty trail and therefore reads as the root —
    /// the safe answer, because every control that goes *up* stops there.
    public var trail: [String] {
        let above = FolderIdentity.key(root).split(separator: "/")
        let here = FolderIdentity.key(url).split(separator: "/")
        guard here.count > above.count, here.starts(with: above) else { return [] }
        return here.dropFirst(above.count).map(String.init)
    }

    public var isAtRoot: Bool { trail.isEmpty }

    /// The folder above this listing, or nil at the tab's own folder.
    ///
    /// Never above the root. The tab is what the sandbox granted, and its
    /// parent was not — so this is a containment rule, not a convenience.
    public var parent: URL? {
        isAtRoot ? nil : url.deletingLastPathComponent()
    }

    /// Where you are, for the line above the list: "Documents / Cowork".
    /// Empty at the root, where the tab already says it.
    public var trailLabel: String {
        isAtRoot ? "" : ([name] + trail).joined(separator: " / ")
    }

    public var fileCount: Int { entries.filter { !$0.isFolder }.count }
    public var folderCount: Int { entries.filter(\.isFolder).count }

    /// What the header prints beside the folder's name.
    public var accessory: String {
        guard state == .listed else { return "" }
        let files = "\(fileCount) \(fileCount == 1 ? "file" : "files")"
        guard folderCount > 0 else { return files }
        return files + " · \(folderCount) \(folderCount == 1 ? "folder" : "folders")"
    }

    /// This folder's entries, in the order the shelf shows things.
    ///
    /// On the folder rather than on `FileShelf`, because two surfaces order
    /// the same rows now — the list, and a peek into a folder that is not the
    /// one being listed. One of them sorting differently would make looking
    /// inside a folder and then going into it rearrange what you just read.
    public func ordered(by sort: FileShelf.SortOrder) -> [ShelfEntry] {
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

    /// Printed in place of rows, rather than leaving an empty box.
    public var emptyMessage: String {
        switch state {
        case .listed: return ""
        case .empty: return "Nothing in \(listingName)."
        case .unavailable: return "\(listingName) is not available right now."
        }
    }
}

/// One line of the list: an entry, and where it sits in the tree.
///
/// The list is no longer flat. A folder row can be opened in place, the way
/// the Finder's list view opens one, and its contents appear indented beneath
/// it rather than replacing what you were looking at. That is what the shelf
/// needed all along: the question "what is in there" is usually asked *while*
/// looking at something else, and every answer that took the list away —
/// navigating, and then a card laid over it — answered a question nobody had
/// asked, which was "take me there".
///
/// Forwards the entry's own properties so that a row still reads as a row.
public struct ShelfRowItem: Equatable, Identifiable, Sendable {
    /// Whether this row has a triangle, and which way it is pointing.
    public enum Disclosure: Equatable, Sendable {
        case open, closed
        /// No triangle: not a folder, or one nothing may look inside — a
        /// folder in the cloud that is not downloaded has no contents to show
        /// without fetching them.
        ///
        /// Named `plain` rather than `none`, which is the trap: through an
        /// Optional, `disclosure == .none` reads as "is nil" and is true for
        /// a row that does not exist rather than for one with no triangle.
        /// A check caught exactly that.
        case plain
    }

    public init(entry: ShelfEntry, depth: Int, disclosure: Disclosure) {
        self.entry = entry
        self.depth = depth
        self.disclosure = disclosure
    }

    public let entry: ShelfEntry
    /// How far in. Zero is the folder being listed.
    public let depth: Int
    public let disclosure: Disclosure

    public var isOpen: Bool { disclosure == .open }

    public var id: String { entry.id }
    public var key: String { entry.key }
    public var name: String { entry.name }
    public var url: URL { entry.url }
    public var isFolder: Bool { entry.isFolder }
    public var isOpenable: Bool { entry.isOpenable }
    public var isEnterable: Bool { entry.isEnterable }
    public var isPreviewable: Bool { entry.isPreviewable }
    public var isCloudPlaceholder: Bool { entry.isCloudPlaceholder }
}
