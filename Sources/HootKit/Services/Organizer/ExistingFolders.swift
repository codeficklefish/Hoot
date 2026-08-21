import Foundation

/// The folders a user has already made inside the watched directory.
///
/// These are the best taxonomy signal available: someone who created a
/// `Books` folder has already said where books go. Hoot should file into
/// those folders rather than inventing near-duplicates beside them
/// ("Ebooks" next to an existing "Books").
public struct ExistingFolders {
    private let names: [String]
    /// Lowercased name -> the folder's real name, preserving the user's casing.
    private let lookup: [String: String]

    public init(in root: URL, fileManager: FileManager = .default) {
        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let folders = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.map(\.lastPathComponent)

        self.names = folders
        self.lookup = Dictionary(folders.map { ($0.lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })
    }

    /// Testing seam.
    public init(names: [String]) {
        self.names = names
        self.lookup = Dictionary(names.map { ($0.lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })
    }

    public var isEmpty: Bool { names.isEmpty }
    public var allNames: [String] { names }

    /// Maps a proposed folder name onto an existing folder when they clearly
    /// mean the same thing, so files join what's already there.
    ///
    /// Deliberately conservative: exact match, plural/singular, or a known
    /// synonym. Loose substring matching would merge "Work" into "Homework".
    public func canonicalName(for proposed: String) -> String {
        let key = proposed.lowercased()

        if let exact = lookup[key] { return exact }

        // "Book" <-> "Books"
        if key.hasSuffix("s"), let singular = lookup[String(key.dropLast())] { return singular }
        if let plural = lookup[key + "s"] { return plural }

        for (synonym, canonical) in Self.synonyms where synonym == key {
            if let existing = lookup[canonical] { return existing }
        }

        return proposed
    }

    /// Common ways of naming the same shelf.
    private static let synonyms: [(String, String)] = [
        ("ebooks", "books"), ("ebook", "books"), ("reading", "books"),
        ("invoices", "finance"), ("receipts", "finance"), ("billing", "finance"),
        ("bills", "finance"), ("taxes", "finance"),
        ("uni", "school"), ("university", "school"), ("college", "school"),
        ("studies", "school"), ("coursework", "school"), ("class", "school"),
        ("photos", "images"), ("pictures", "images"), ("screenshots", "images"),
        ("apps", "installers"), ("software", "installers"),
        ("videos", "media"), ("music", "media"), ("audio", "media"),
        ("zips", "archives"), ("compressed", "archives")
    ]
}
