import Foundation

/// Detects files that live in the cloud rather than on this Mac.
///
/// iCloud Drive, Dropbox and Google Drive all leave *placeholders* on disk:
/// entries with a name and a size that contain no data until something opens
/// them. Opening one silently starts a download — which for a folder of large
/// files means gigabytes over someone's connection, without their asking, for
/// nothing more than a filing suggestion.
///
/// Hoot reads a great deal from inside files, so it has to check first.
/// Metadata (name, size, dates) is safe to read and never triggers a
/// download; content is not.
enum CloudStorage {

    /// True when reading this file's contents would pull it down from a server.
    static func isPlaceholder(_ url: URL) -> Bool {
        if isDataless(url) { return true }
        return isUndownloadedICloudItem(url)
    }

    /// `SF_DATALESS`, which Swift's Darwin overlay does not expose. Only the
    /// system sets it, so tests exercise `isDataless(flags:)` directly rather
    /// than trying to fake a placeholder on disk.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// Pure form of the check, kept separate so it can be tested.
    static func isDataless(flags: UInt32) -> Bool {
        flags & datalessFlag != 0
    }

    /// The general signal, set by macOS File Provider for any sync service:
    /// the file exists in the directory but its data is not local.
    private static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return isDataless(flags: info.st_flags)
    }

    /// iCloud reports its own state, including partially-downloaded items.
    private static func isUndownloadedICloudItem(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else { return false }

        guard values.isUbiquitousItem == true else { return false }
        guard let status = values.ubiquitousItemDownloadingStatus else { return true }
        // `.current` is fully downloaded and up to date. Anything else would
        // need fetching before it could be read.
        return status != .current
    }
}
