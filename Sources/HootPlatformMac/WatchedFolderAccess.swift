import Foundation
import HootKit

/// Holds onto the one folder the user has granted Hoot access to.
///
/// Under the App Sandbox, choosing a folder in the open panel grants access
/// only for as long as the app runs. A security-scoped bookmark makes that
/// grant durable, so Hoot can keep watching the same folder after a restart
/// without asking again — and still has access to nothing else.
public final class WatchedFolderAccess {
    private static let bookmarkKey = "watched.folder.bookmark"

    private let defaults: UserDefaults
    /// The URL whose security scope is currently held open, so it can be
    /// balanced with a matching stop.
    private var activeURL: URL?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Stores a durable reference to `url` and begins accessing it.
    public func remember(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        } catch {
            // Not fatal: the folder still works for this launch, it just
            // won't be remembered next time.
            NSLog("Hoot: could not bookmark \(url.path): \(error)")
        }
        beginAccess(to: url)
    }

    /// Restores the previously granted folder, if there is one and it's still
    /// reachable. Returns nil when nothing was granted or the bookmark is
    /// stale (the folder was deleted, renamed, or moved to another volume).
    public func restore() -> URL? {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // The folder moved, so the bookmark has to be re-issued from
                // the resolved URL — but access must be open before that.
                // Resolving a bookmark grants nothing on its own, and writing
                // a new security-scoped bookmark is itself a use of the
                // resource. Re-issuing first left `remember` logging a failure
                // and the stale bookmark still in defaults, so the same
                // resolve-and-fail repeated on every launch and the user was
                // asked for the folder again each time.
                beginAccess(to: url)
                remember(url)
                return url
            }

            beginAccess(to: url)
            return url
        } catch {
            NSLog("Hoot: stored folder is no longer reachable: \(error)")
            forget()
            return nil
        }
    }

    public func forget() {
        endAccess()
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    private func beginAccess(to url: URL) {
        // Already holding this exact folder open: starting again would need a
        // matching extra stop to balance, and the stop-then-start in the
        // general path would briefly drop access Hoot is relying on.
        guard activeURL != url else { return }

        endAccess()
        // Outside the sandbox this is a no-op that reports false; access works
        // regardless, so a failure here shouldn't block anything.
        if url.startAccessingSecurityScopedResource() {
            activeURL = url
        }
    }

    private func endAccess() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
    }

    deinit {
        endAccess()
    }
}
