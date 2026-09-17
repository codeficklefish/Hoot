import Foundation

/// Reads one folder into rows.
///
/// Pure and free of the main actor, so the app can run it off to the side and
/// hand back the result. It is the only thing in this module that touches a
/// disk, and it touches it exactly once per folder: the properties every row
/// needs are prefetched in the same call that lists the directory, rather
/// than asked for again per file.
public enum ShelfReader {

    /// Read enough to count past what is shown. The list displays
    /// `FileShelf.maxRows`; reading a few times that many means a folder can
    /// be sorted three different ways without re-reading, while a Downloads
    /// folder with ten thousand files in it never becomes ten thousand values
    /// in order to print nine rows.
    public static let defaultLimit = FileShelf.maxRows * 8

    public static func read(
        _ folder: URL,
        limit: Int = defaultLimit,
        fileManager: FileManager = .default
    ) -> ShelfFolder {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]

        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            // Told apart from empty deliberately. A folder on an ejected disk
            // is not a folder with nothing in it, and saying so lets the panel
            // keep the tab rather than dropping a folder the user chose.
            return ShelfFolder(url: folder, state: .unavailable, entries: [])
        }

        var entries: [ShelfEntry] = []
        for url in contents {
            guard entries.count < limit else { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let byteCount = Int64(values?.fileSize ?? 0)

            // Folders are listed here where the organizer ignores them, which
            // is why `isJunk` is asked rather than `isIgnored`: one is a
            // question about the file, the other about what Hoot does next.
            guard !FileAnalyzer.isJunk(url, fileSize: Int(byteCount)) else { continue }

            entries.append(
                ShelfEntry(
                    url: url,
                    symbolName: isDirectory ? "folder" : FileItem.Kind(forExtension: url.pathExtension).symbolName,
                    isFolder: isDirectory,
                    byteCount: byteCount,
                    childCount: isDirectory ? childCount(of: url, fileManager: fileManager) : 0,
                    sortDate: values?.creationDate ?? values?.contentModificationDate,
                    isCloudPlaceholder: isPlaceholder(values)
                )
            )
        }

        return ShelfFolder(
            url: folder,
            state: entries.isEmpty ? .empty : .listed,
            entries: entries
        )
    }

    /// How many things a folder holds, for its size column.
    ///
    /// Shallow and unfiltered on purpose: it answers "how much is in here",
    /// which is the Finder's question, not "how much would Hoot file", which
    /// is a different one and would cost a recursive walk per row.
    private static func childCount(of folder: URL, fileManager: FileManager) -> Int {
        (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).count) ?? 0
    }

    /// In the cloud and not downloaded. Safety rule 5 forbids opening one, so
    /// the row has to know before anything offers to preview it.
    private static func isPlaceholder(_ values: URLResourceValues?) -> Bool {
        guard values?.isUbiquitousItem == true else { return false }
        guard let status = values?.ubiquitousItemDownloadingStatus else { return false }
        return status != .current
    }
}
