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
    public static func isIgnored(_ url: URL) -> Bool {
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
        if hasBlankName {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size == 0 { return true }
        }

        // System / well-known noise files.
        let ignoredNames: Set<String> = [".DS_Store", ".localized", "Thumbs.db", "desktop.ini"]
        if ignoredNames.contains(name) { return true }

        // A partial download isn't a real file yet. Ignoring it outright is
        // safe: when the download finishes the file is *renamed* to its final
        // name, which the watcher sees as a new arrival.
        if isInProgressDownload(url) { return true }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }

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
