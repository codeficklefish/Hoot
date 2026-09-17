import Foundation
import HootKit

/// The folders Hoot has been shown but will never touch.
///
/// The same sandbox machinery as `WatchedFolderAccess` and a different policy
/// on top of it, because the two answer to different failures. One folder
/// that has gone missing means Hoot has nothing to organise and should say
/// so; one shelf folder missing out of five means four still work, and
/// throwing the list away would be a far worse answer than showing a gap.
public final class ShelfFolderAccess: FolderSetAccessing {
    /// One key holding an array, not a key per folder. The order is
    /// user-visible — it is the order of the tabs at the notch — so numbered
    /// keys would need a separate index key beside them, at which point the
    /// array *is* the index. It also makes forgetting everything one removal.
    private static let bookmarksKey = "shelf.folder.bookmarks"

    private let defaults: UserDefaults
    private let scopes = SecurityScopes()

    /// Its own scopes, not shared with the watched folder's. If the same
    /// folder is both, two scopes are opened on it and each is balanced by
    /// its owner — sharing one would let whichever finished first close
    /// access the other was still relying on.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func restoreAll() -> (folders: [URL], dropped: Int) {
        guard let stored = defaults.array(forKey: Self.bookmarksKey) as? [Data] else {
            return ([], 0)
        }

        var folders: [URL] = []
        var keep: [Data] = []
        var dropped = 0
        var changed = false

        for bookmark in stored {
            do {
                let (url, isStale) = try FolderBookmark.resolve(bookmark)

                // Access first, then re-issue — the same ordering the watched
                // folder's restore depends on, and for the same reason:
                // writing a security-scoped bookmark is itself a use of the
                // resource, so re-issuing before opening fails and leaves the
                // stale data in place to fail again next launch.
                scopes.open(url)

                guard !folders.contains(where: { FolderIdentity.key($0) == FolderIdentity.key(url) })
                else { changed = true; continue }

                if isStale {
                    keep.append((try? FolderBookmark.make(for: url)) ?? bookmark)
                    changed = true
                } else {
                    keep.append(bookmark)
                }
                folders.append(url)
            } catch {
                // This one alone. The single-folder adapter calls `forget()`
                // on any throw, which is right when there is one folder and
                // catastrophic for a list.
                NSLog("Hoot: a shelf folder is no longer reachable: \(error)")
                dropped += 1
                changed = true
            }
        }

        // Written back once, after the whole list has been read, rather than
        // per entry.
        if changed { defaults.set(keep, forKey: Self.bookmarksKey) }
        return (folders, dropped)
    }

    @discardableResult
    public func remember(_ url: URL) -> Bool {
        var stored = defaults.array(forKey: Self.bookmarksKey) as? [Data] ?? []

        // Already here? Opening the scope again is harmless and idempotent,
        // but a second bookmark for the same folder would show as a second
        // tab for it.
        if resolvedURLs(in: stored).contains(where: {
            FolderIdentity.key($0) == FolderIdentity.key(url)
        }) {
            scopes.open(url)
            return false
        }

        scopes.open(url)
        do {
            stored.append(try FolderBookmark.make(for: url))
            defaults.set(stored, forKey: Self.bookmarksKey)
        } catch {
            // As with the watched folder: usable now, just not remembered.
            NSLog("Hoot: could not bookmark shelf folder \(url.path): \(error)")
        }
        return true
    }

    public func forget(_ url: URL) {
        let stored = defaults.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        let wanted = FolderIdentity.key(url)
        let keep = stored.filter { bookmark in
            guard let resolved = try? FolderBookmark.resolve(bookmark).url else { return true }
            return FolderIdentity.key(resolved) != wanted
        }
        defaults.set(keep, forKey: Self.bookmarksKey)
        scopes.close(url)
    }

    /// Resolving only to compare. Deliberately does not open a scope: this
    /// answers "is it already on the list", which is a question about the
    /// list rather than a use of the folder.
    private func resolvedURLs(in bookmarks: [Data]) -> [URL] {
        bookmarks.compactMap { try? FolderBookmark.resolve($0).url }
    }
}
