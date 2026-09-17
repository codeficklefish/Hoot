import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// The folders the notch lists, and nothing it does to them.
///
/// Every operation here reads. That is the whole reason the shelf may hold
/// several folders while the organizer holds one: safety rules 1 through 4
/// are all about writing, so a surface that cannot write cannot break them.
/// If something in this file ever moves, renames or deletes a file, that
/// reasoning is gone and the privacy page is wrong.
extension AppState {

    /// How long a just-read folder is considered current. Pointing at the
    /// notch and away again is one gesture, not four reads.
    private static let shelfReadInterval: TimeInterval = 1

    // MARK: - Which folders

    func restoreShelf() {
        let (folders, dropped) = shelfAccess.restoreAll()
        var restored = FileShelf()
        for url in folders {
            restored.add(ShelfFolder(url: url, state: .empty, entries: []))
        }
        shelf = restored

        if dropped > 0 {
            // Said rather than swallowed. A folder vanishing from the tab row
            // with no explanation reads as Hoot losing it.
            report(
                UserFacingIssue(
                    title: dropped == 1
                        ? "A shelf folder is no longer there."
                        : "\(dropped) shelf folders are no longer there.",
                    suggestion: "They were moved or deleted, so they have been taken off the shelf.",
                    severity: .warning
                )
            )
        }
        Task { await refreshShelf(force: true) }
    }

    /// Adds folders to the shelf. Several at once, because someone adding
    /// Desktop is usually also adding Documents.
    ///
    /// The same two precautions as `presentFolderPicker`, and for the same
    /// documented reasons: an accessory app has to activate before its panel
    /// takes key focus, and `runModal()` inside the popover's event-tracking
    /// loop swallows clicks.
    /// The places people actually leave things.
    ///
    /// Offered as one-click destinations because "Desktop" is a word someone
    /// has in mind, not a path they want to navigate to. The sandbox still
    /// requires them to choose it — there is no automatic access to any of
    /// these — but a panel already standing in the right folder turns that
    /// into a confirmation rather than an errand.
    static var standardFolders: [(name: String, url: URL)] {
        let manager = FileManager.default
        let wanted: [(String, FileManager.SearchPathDirectory)] = [
            ("Desktop", .desktopDirectory),
            ("Documents", .documentDirectory),
            ("Downloads", .downloadsDirectory),
            ("Pictures", .picturesDirectory)
        ]
        return wanted.compactMap { name, directory in
            manager.urls(for: directory, in: .userDomainMask).first.map { (name, $0) }
        }
    }

    /// True when that folder is not already a tab.
    func isOnShelf(_ url: URL) -> Bool {
        shelf.folders.contains { FolderIdentity.same($0.url, url) }
    }

    func presentShelfFolderPicker(startingAt start: URL? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor [weak self] in
            guard let self else { return }

            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "Add to Shelf"
            panel.message = "Choose folders for the notch to show. Hoot only reads these."
            // Standing in the folder being offered. With nothing selected,
            // an open panel in directory mode returns the directory it is
            // showing — so "Add Desktop" is one button and one confirm.
            panel.directoryURL = start
                ?? FileManager.default.urls(for: .userDirectory, in: .localDomainMask).first

            panel.begin { response in
                guard response == .OK else { return }
                let picked = panel.urls
                Task { @MainActor in
                    for url in picked { self.addShelfFolder(url) }
                }
            }

            panel.makeKeyAndOrderFront(nil)
        }
    }

    func addShelfFolder(_ url: URL) {
        // The cap is the shelf's rule, so it is asked first — a folder the
        // shelf will not show should not have its grant stored either.
        guard shelf.folders.count < FileShelf.maxFolders else {
            lastMessage = "The shelf holds \(FileShelf.maxFolders) folders. Remove one first."
            return
        }
        guard shelfAccess.remember(url) else { return }
        guard shelf.add(ShelfFolder(url: url, state: .empty, entries: [])) else { return }
        Task { await refreshShelf(force: true) }
    }

    func removeShelfFolder(_ url: URL) {
        shelfAccess.forget(url)
        shelf.remove(url)
        // Whatever the cursor landed on may never have been read — a folder
        // restored at launch carries no rows until something asks for them,
        // so removing a tab would otherwise leave the next one looking empty.
        shelfHandoff = nil
        Task { await refreshShelf(force: true) }
    }

    // MARK: - Reading them

    /// Re-reads the folder being shown.
    ///
    /// Read on opening rather than watched. `FileWatcher` exists to answer
    /// "has this download finished, so it can be organized" — hence its
    /// stability polling — and the shelf has no such question: a half-written
    /// file appearing in a list for a moment costs nothing. Holding a
    /// file-system source open all day for a panel nobody is looking at
    /// costs more than reading it when they are.
    func refreshShelf(force: Bool = false) async {
        guard let folder = shelf.current else { return }

        if !force, let last = lastShelfRead,
           Date().timeIntervalSince(last) < Self.shelfReadInterval {
            return
        }
        lastShelfRead = Date()

        let url = folder.url
        let read = await Task.detached(priority: .userInitiated) {
            ShelfReader.read(url)
        }.value

        // An unchanged folder reads back equal, so this assignment publishes
        // nothing and the panel does not redraw under the pointer.
        shelf.replace(read)
    }

    // MARK: - Moving between them

    func showShelfFolder(at index: Int) {
        shelf.show(folderAt: index)
        Task { await refreshShelf(force: true) }
    }

    func showNextShelfFolder() {
        shelf.showNext()
        Task { await refreshShelf(force: true) }
    }

    func showPreviousShelfFolder() {
        shelf.showPrevious()
        Task { await refreshShelf(force: true) }
    }

    func cycleShelfSort() {
        shelf.sort = shelf.sort.next
    }

    func selectShelfEntry(_ id: String?) {
        shelf.select(id)
    }

    // MARK: - The two things it hands off to something else

    /// How many files in a shelf folder the plan would move.
    ///
    /// Only ever non-zero for the watched folder, because that is the only
    /// folder there is a plan for — which is the read-many-write-one rule
    /// showing through in the interface rather than being asserted in a
    /// comment. Everywhere else the button is simply absent.
    func untidyCount(in folder: URL) -> Int {
        guard let plan, let watchedFolder else { return 0 }
        guard FolderIdentity.same(folder, watchedFolder) else { return 0 }
        return plan.allMoves.count
    }

    /// Hands the folder over to the review window.
    ///
    /// The shelf itself never moves anything — this is a door, not a verb.
    /// Everything about deciding where a file goes stays where it already
    /// was, which is the reason the walk came out of the notch in the first
    /// place.
    func openReviewForTidying() {
        guard let folder = shelf.current else { return }
        shelfHandoff = shelf.tidyMessage(untidy: untidyCount(in: folder.url))
        openReviewWindow?()
    }

    func dismissShelfHandoff() {
        shelfHandoff = nil
    }

    /// Opens a file the way double-clicking it in the Finder would.
    ///
    /// Still not a write: handing a file to the application that owns it is
    /// what the Finder does, and Hoot does not touch the file either way.
    /// A folder opens in the Finder rather than being descended into — the
    /// shelf lists, it does not browse.
    func openShelfEntry(_ entry: ShelfEntry) {
        if entry.isFolder {
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        } else {
            NSWorkspace.shared.open(entry.url)
        }
        shelfHandoff = "Opened \(entry.name)"
    }

    /// Hands the current folder, or the picked file, to the Finder.
    func revealInFinder() {
        if let picked = shelf.pickedEntry {
            NSWorkspace.shared.activateFileViewerSelecting([picked.url])
        } else if let folder = shelf.current {
            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
        } else {
            return
        }
        shelfHandoff = shelf.revealMessage
    }
}
