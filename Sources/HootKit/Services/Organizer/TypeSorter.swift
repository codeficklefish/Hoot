import Foundation

/// Sorts files by what they are, using nothing but the name and extension.
///
/// Deliberately dumber than the rest of the engine. No file is opened, no
/// model is consulted, and the answer for a given filename is the same every
/// time — which is the property people are choosing when they pick this mode.
/// If it ever needed to read a file to decide, it would have stopped being
/// the simple option.
public enum TypeSorter {

    /// Screenshots are the one bucket the extension cannot supply: a
    /// screenshot is a PNG like any other PNG, and the only thing separating
    /// it is the name the capture tool gave it.
    ///
    /// They earn their own folder because they arrive in volume and are
    /// almost never wanted next to photographs. Matching is by the prefixes
    /// the common tools use — macOS ("Screenshot 2026-09-12 at…", and "Screen
    /// Shot…" before Mojave), CleanShot X and Shottr.
    ///
    /// A Mac running in another language names them differently, and those
    /// files fall through to Images rather than being guessed at. Putting a
    /// photograph in Screenshots is a worse mistake than leaving a screenshot
    /// in Images, because the user goes looking for it under the wrong idea
    /// of where it went.
    private static let screenshotPrefixes = [
        "screenshot",
        "screen shot",
        "cleanshot",
        "scr-"        // Shottr's default, e.g. SCR-20260912-abcd.png
    ]

    /// Video and audio share one `FileItem.Kind`, but not one folder: nobody
    /// looking for a song expects to wade through screen recordings.
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]

    public static func isScreenshot(_ file: FileItem) -> Bool {
        guard file.kind == .image else { return false }
        let name = file.filename.lowercased()
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }

    /// The folder this file belongs in, or nil when its type is genuinely
    /// unknown.
    ///
    /// Nil rather than an "Other" folder on purpose. A junk drawer named by
    /// the app is worse than leaving the file where the user put it: it moves
    /// something they may be looking for, and tells them nothing in return.
    public static func folder(for file: FileItem) -> String? {
        if isScreenshot(file) { return "Screenshots" }

        switch file.kind {
        case .image: return "Images"
        case .pdf: return "PDFs"
        case .document, .text: return "Documents"
        case .spreadsheet: return "Spreadsheets"
        case .book: return "Books"
        case .archive: return "Archives"
        case .installer: return "Installers"
        case .media:
            return videoExtensions.contains(file.fileExtension.lowercased())
                ? "Videos" : "Audio"
        case .other: return nil
        }
    }

    /// Why this file is going where it is going — shown in review, where the
    /// reason for a move has to be checkable rather than taken on trust.
    public static func reason(for file: FileItem) -> String {
        if isScreenshot(file) {
            return "Named like a screenshot, and it is an image."
        }
        let ext = file.fileExtension.uppercased()
        return ext.isEmpty
            ? "Sorted by file type."
            : "A \(ext) file, sorted by type."
    }

    /// Every folder this mode can produce, for explaining it before the user
    /// has any files in front of them.
    public static let allFolders = [
        "Screenshots", "Images", "PDFs", "Documents", "Spreadsheets",
        "Books", "Videos", "Audio", "Archives", "Installers"
    ]
}
