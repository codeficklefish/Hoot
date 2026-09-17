import Foundation

/// Whether two URLs name the same folder.
///
/// They very often do not compare equal when they do. A security-scoped
/// bookmark resolves to the canonical path with a trailing slash —
/// `/private/tmp/x/Alpha/` — where the URL it was made from was
/// `/tmp/x/Alpha`, because `/tmp` is a symlink. Comparing those with `==`
/// made adding a shelf folder twice give it two tabs, and made forgetting
/// one do nothing at all.
///
/// In the engine rather than beside the sandbox code that first needed it,
/// because three things now ask this question — the bookmark store, the
/// shelf's tab list, and the check for whether a shelf folder is also the
/// folder being organized — and a rule asked in three places should be
/// written in one. `Organizer.verifyContained` resolves the same way before
/// deciding containment.
public enum FolderIdentity {

    /// The one spelling of a path that everything can agree on.
    public static func key(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func same(_ left: URL, _ right: URL) -> Bool {
        key(left) == key(right)
    }
}
