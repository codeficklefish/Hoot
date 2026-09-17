import Foundation
import HootKit

/// Making a sandbox grant durable, and holding it open.
///
/// Both of Hoot's folder adapters need exactly this and nothing else — one
/// for the folder it organises, one for the folders it only lists — so the
/// mechanism lives here once and the *policy* lives in each of them. What
/// differs between the two is how many grants they keep and what they do
/// when one goes bad, which is not a difference `URL.bookmarkData` cares
/// about.
enum FolderBookmark {

    static func make(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

/// Security scopes held open, each balanced exactly once.
///
/// `startAccessingSecurityScopedResource()` must be matched by a stop, and
/// calling it twice for one URL needs two stops — so what is actually open is
/// tracked rather than assumed. Outside the sandbox it is a no-op returning
/// false; access works regardless, which is why a false return is recorded as
/// "nothing to balance" rather than treated as a failure.
final class SecurityScopes {
    /// Keyed by canonical path, valued by the URL access was actually opened
    /// with — the stop has to be sent to the same one the start was.
    private var held: [String: URL] = [:]

    func open(_ url: URL) {
        let key = FolderIdentity.key(url)
        guard held[key] == nil else { return }
        if url.startAccessingSecurityScopedResource() {
            held[key] = url
        }
    }

    func close(_ url: URL) {
        guard let started = held.removeValue(forKey: FolderIdentity.key(url)) else { return }
        started.stopAccessingSecurityScopedResource()
    }

    func closeAll() {
        for url in held.values { url.stopAccessingSecurityScopedResource() }
        held.removeAll()
    }

    deinit { closeAll() }
}
