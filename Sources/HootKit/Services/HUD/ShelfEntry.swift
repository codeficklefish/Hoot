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
        self.symbolName = symbolName
        self.isFolder = isFolder
        self.byteCount = byteCount
        self.childCount = childCount
        self.sortDate = sortDate
        self.isCloudPlaceholder = isCloudPlaceholder
    }

    public let url: URL
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

    /// Whether anything may open this to look inside it.
    ///
    /// A rule rather than a `guard` in the view, so that it can be checked.
    /// Quick Look on a file that lives in the cloud and is not downloaded
    /// would fetch it — safety rule 5 says Hoot never starts a download
    /// nobody asked for, and this is that rule reaching a surface which is
    /// not the organizer. A folder is not previewable either; the Finder is
    /// what opens one of those.
    public var isPreviewable: Bool {
        !isCloudPlaceholder && !isFolder
    }

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
public struct ShelfFolder: Equatable, Identifiable, Sendable {
    /// Why a folder might have no rows. Told apart on purpose: an empty
    /// Downloads folder is good news, and a folder on an ejected disk is not,
    /// and printing the same line for both would be a small lie.
    public enum State: Equatable, Sendable {
        case listed, empty, unavailable
    }

    public init(url: URL, state: State, entries: [ShelfEntry]) {
        self.url = url
        self.state = state
        self.entries = entries
    }

    public let url: URL
    public let state: State
    public let entries: [ShelfEntry]

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }

    public var fileCount: Int { entries.filter { !$0.isFolder }.count }
    public var folderCount: Int { entries.filter(\.isFolder).count }

    /// What the header prints beside the folder's name.
    public var accessory: String {
        guard state == .listed else { return "" }
        let files = "\(fileCount) \(fileCount == 1 ? "file" : "files")"
        guard folderCount > 0 else { return files }
        return files + " · \(folderCount) \(folderCount == 1 ? "folder" : "folders")"
    }

    /// Printed in place of rows, rather than leaving an empty box.
    public var emptyMessage: String {
        switch state {
        case .listed: return ""
        case .empty: return "Nothing in \(name)."
        case .unavailable: return "\(name) is not available right now."
        }
    }
}
