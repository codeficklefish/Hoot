import Foundation

/// Turns a raw URL from the FileWatcher into a FileItem, applying the
/// safety rules that decide whether a path is even eligible for analysis.
/// This is discovery + metadata only — no text extraction, no classification.
public struct FileAnalyzer {

    /// Filenames/extensions that mean "still being written" (partial downloads).
    private static let inProgressExtensions: Set<String> = [
        "download", "crdownload", "part", "partial"
    ]

    /// True if this path should never be surfaced to the rest of Hoot.
    ///
    /// Reads the two facts it needs off disk, then defers to the pure rules
    /// below. Kept as the entry point everything already calls.
    public static func isIgnored(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return isIgnored(url, isDirectory: exists && isDirectory.boolValue, fileSize: size)
    }

    /// The same question, with the disk already read.
    ///
    /// A directory is ignored here because everything downstream of this
    /// organizes *files*. It is a separate clause from `isJunk` rather than
    /// folded into it, because whether a folder should be shown depends on
    /// who is asking: the organizer never touches one, and the shelf lists
    /// them the way the Finder does.
    public static func isIgnored(_ url: URL, isDirectory: Bool, fileSize: Int) -> Bool {
        isDirectory || isJunk(url, fileSize: fileSize)
    }

    /// Whether this is an artifact rather than a file someone has: a dotfile,
    /// an Office lock file, a half-finished download, a system leftover.
    ///
    /// Pure — it touches nothing and can be checked without a sandbox, which
    /// is the point of separating it. Directories are not judged.
    public static func isJunk(_ url: URL, fileSize: Int) -> Bool {
        let name = url.lastPathComponent

        if name.hasPrefix(".") { return true }
        if name == "Icon\r" { return true }

        // Office lock/owner files ("~$Report.docx") appear while a document is
        // open and vanish when it closes — never the user's actual file.
        if name.hasPrefix("~$") || name.hasPrefix("~") && name.contains("$") { return true }

        // A blank name usually means a junk artifact — but not always: a real
        // image can be saved with an empty name. Hiding a file that holds real
        // data is worse than showing one with an odd name, so only skip these
        // when they're also empty.
        let hasBlankName = (name as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBlankName, fileSize == 0 { return true }

        // System / well-known noise files.
        let ignoredNames: Set<String> = [".DS_Store", ".localized", "Thumbs.db", "desktop.ini"]
        if ignoredNames.contains(name) { return true }

        // A partial download isn't a real file yet. Ignoring it outright is
        // safe: when the download finishes the file is *renamed* to its final
        // name, which the watcher sees as a new arrival.
        if isInProgressDownload(url) { return true }

        return false
    }

    /// True if the extension itself marks the file as a temporary,
    /// still-downloading artifact (e.g. Safari's ".download").
    public static func isInProgressDownload(_ url: URL) -> Bool {
        inProgressExtensions.contains(url.pathExtension.lowercased())
    }

    /// Builds a FileItem for a path that has already passed the ignore checks.
    public static func analyze(_ url: URL) -> FileItem? {
        guard !isIgnored(url) else { return nil }
        return FileItem(url: url)
    }
}
