import Foundation

/// A file discovered by the FileWatcher, with the basic metadata
/// collected during the discovery/analysis stage (no content extraction yet).
public struct FileItem: Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let filename: String
    public let fileExtension: String
    public let fileSize: Int64
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let parentFolder: URL

    /// True when the file's contents live in the cloud, so reading them would
    /// start a download. Its name, size and dates are still available.
    public var isCloudPlaceholder: Bool {
        CloudStorage.isPlaceholder(url)
    }

    /// Identity for caching: same path, size and modification date means the
    /// same file, so previous analysis of it still applies.
    public var signature: String {
        let modified = modifiedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "\(url.path)|\(fileSize)|\(modified)"
    }

    public var displaySize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// A coarse, extension-based file kind used only for iconography.
    /// Real classification (project/category) comes from a FileClassifier,
    /// never from this.
    public enum Kind {
        case document, spreadsheet, image, pdf, text, book, archive, installer, media, other

        public var symbolName: String {
            switch self {
            case .document: return "doc.text"
            case .spreadsheet: return "tablecells"
            case .image: return "photo"
            case .pdf: return "doc.richtext"
            case .text: return "text.alignleft"
            case .book: return "book"
            case .archive: return "doc.zipper"
            case .installer: return "shippingbox"
            case .media: return "play.rectangle"
            case .other: return "doc"
            }
        }

        /// True when the extension alone tells us what this file is. Such
        /// files can be filed by type with confidence, even when nothing in
        /// the name hints at which project they belong to.
        public var isRecognized: Bool {
            self != .other
        }
    }

    public var kind: Kind {
        switch fileExtension.lowercased() {
        case "docx", "doc", "pages", "rtf", "odt":
            return .document
        case "xlsx", "xls", "csv", "numbers", "tsv":
            return .spreadsheet
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "webp", "bmp", "svg":
            return .image
        case "pdf":
            return .pdf
        case "txt", "md", "markdown":
            return .text
        case "epub", "mobi", "azw", "azw3", "djvu":
            return .book
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2":
            return .archive
        case "dmg", "pkg", "app", "iso":
            return .installer
        case "mp4", "mov", "m4v", "avi", "mkv", "mp3", "m4a", "wav", "aiff":
            return .media
        default:
            return .other
        }
    }

    public init?(url: URL) {
        let fm = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]) else {
            return nil
        }
        guard fm.fileExists(atPath: url.path) else { return nil }

        self.id = UUID()
        self.url = url
        self.filename = url.lastPathComponent
        self.fileExtension = url.pathExtension
        self.fileSize = Int64(values.fileSize ?? 0)
        self.createdAt = values.creationDate
        self.modifiedAt = values.contentModificationDate
        self.parentFolder = url.deletingLastPathComponent()
    }
}
