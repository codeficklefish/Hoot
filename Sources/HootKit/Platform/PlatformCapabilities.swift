import Foundation

/// The things the engine needs a platform to do for it.
///
/// Every one of these is answered by a different framework on macOS and on
/// Windows — reading a PDF, recognising words in a picture, watching a folder,
/// showing a notification. The engine states what it needs and stays out of
/// how; each platform supplies an adapter.
///
/// This is the whole surface between `HootKit` and the operating system. If
/// something new is needed from the platform, it is declared here rather than
/// imported into the engine.

// MARK: - Reading what is inside a file

/// What could be established from a file's contents.
public struct ExtractedEvidence: Equatable, Sendable {
    public let excerpt: String
    /// True when the excerpt is text that genuinely exists in the file.
    ///
    /// Words on a photographed receipt mean what they say; "appears to show a
    /// bridge" is a guess about a picture. Only the former is strong enough to
    /// justify putting a file in someone's project folder.
    public let isTextual: Bool

    public init(excerpt: String, isTextual: Bool) {
        self.excerpt = excerpt
        self.isTextual = isTextual
    }
}

/// Reads text out of a file: documents, spreadsheets, archives, and pictures
/// of words.
public protocol TextExtracting: Sendable {
    /// Returns nil when nothing readable could be established — including when
    /// the file is a cloud placeholder that must not be downloaded.
    func evidence(for file: FileItem) -> ExtractedEvidence?
}

public extension TextExtracting {
    /// Convenience for callers that only need the text.
    public func excerpt(for file: FileItem) -> String? {
        evidence(for: file)?.excerpt
    }
}

// MARK: - Decompression

/// Inflates a raw DEFLATE stream — the one thing `ZipReader` cannot do with
/// Foundation alone. macOS has the Compression framework; Windows has zlib.
public protocol ArchiveInflating: Sendable {
    /// - Parameter expectedSize: the uncompressed size the archive claims,
    ///   already bounded by the caller.
    /// - Returns: the inflated bytes, or nil if the stream is unusable.
    func inflate(_ deflated: Data, expectedSize: Int) -> Data?
}

// MARK: - Watching a folder

/// Reports files appearing in one directory, once they have finished being
/// written.
public protocol FileWatching: AnyObject {
    var onNewFile: ((URL) -> Void)? { get set }
    func start(watching folder: URL) throws
    func stop()
}

// MARK: - Holding on to the folder the user chose

/// Keeps the one folder Hoot was given, across launches.
///
/// Every platform makes this its own problem. macOS sandboxes the grant, so the
/// folder has to be stored as a security-scoped bookmark and re-opened on each
/// launch; Windows has no equivalent and a stored path is enough. The engine
/// only needs to know that a folder can be remembered, asked for again, and
/// given back.
///
/// Class-bound because an implementation may hold an operating-system resource
/// open for as long as the grant lasts, and has to balance that when it goes.
public protocol FolderAccessing: AnyObject {
    /// Stores a durable reference to `url`, and opens access to it.
    func remember(_ url: URL)

    /// The folder granted on a previous launch, with access opened, or nil when
    /// there was none or it is no longer reachable.
    func restore() -> URL?

    /// Discards the grant and closes access.
    func forget()
}

// MARK: - Holding on to the folders the user only wants to look at

/// Keeps a *set* of folders the user has shown Hoot, across launches.
///
/// Separate from `FolderAccessing` rather than a generalisation of it, and
/// the separation is the design. That protocol is the grant for the one
/// folder Hoot *organises*; widening it to a keyed map would make every
/// caller ask "which folder?" about a question that has exactly one answer,
/// and would quietly invite a second root into the containment rule that
/// safety rule 4 rests on.
///
/// These folders are only ever read. That is what makes having several of
/// them affordable: every safety rule in this project is about writing, so a
/// surface that cannot write adds no new way for any of them to fail.
public protocol FolderSetAccessing: AnyObject {
    /// Every folder remembered, in the order they were added, with access
    /// opened. Entries that no longer resolve are dropped, and counted so
    /// the caller can say so rather than silently losing one.
    func restoreAll() -> (folders: [URL], dropped: Int)

    /// Opens access and stores a durable reference. False when that folder
    /// was already on the list.
    @discardableResult func remember(_ url: URL) -> Bool

    /// Discards one grant and closes its access. The rest are untouched.
    func forget(_ url: URL)
}

// MARK: - Telling the user

/// Posts a notification when files are waiting. Deliberately narrow: Hoot has
/// exactly one thing it ever needs to say unprompted.
@MainActor
public protocol Notifying {
    func notifyFilesWaiting(count: Int, topGroup: String?) async
    func clearPending()
}
