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
            restored.add(ShelfFolder(root: url, state: .empty, entries: []))
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
        shelf.folders.contains { FolderIdentity.same($0.root, url) }
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
        guard shelf.add(ShelfFolder(root: url, state: .empty, entries: [])) else { return }
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

        if !force, Date().timeIntervalSince(lastShelfRead) < Self.shelfReadInterval {
            return
        }
        lastShelfRead = Date()

        await list(folder.url, under: folder.root)
    }

    /// Reads one directory and puts it in its tab.
    ///
    /// `root` rather than the directory itself, so a listing below the tab
    /// still belongs to the tab: `FileShelf.replace` matches on the root, and
    /// the way back up is measured from it.
    private func list(_ url: URL, under root: URL) async {
        let read = await Task.detached(priority: .userInitiated) {
            ShelfReader.read(url, root: root)
        }.value

        // An unchanged folder reads back equal, so this assignment publishes
        // nothing and the panel does not redraw under the pointer.
        shelf.replace(read)
        await relistOpenFolders()
    }

    /// Re-reads the folders that are open in place.
    ///
    /// Otherwise a list that refreshed would be current at the top level and
    /// minutes old two rows below it, which is a worse lie than being old
    /// throughout. One detached pass for all of them, and `refreshOpen`
    /// discards anything closed while it was running.
    private func relistOpenFolders() async {
        let folders = shelf.openFolders
        guard !folders.isEmpty else { return }

        let reads = await Task.detached(priority: .userInitiated) { () -> [String: ShelfFolder] in
            var out: [String: ShelfFolder] = [:]
            for url in folders {
                out[FolderIdentity.key(url)] = ShelfReader.read(url, root: url)
            }
            return out
        }.value

        shelf.refreshOpen(reads)
    }

    // MARK: - Going into one, and coming back out

    /// Lists what is inside a folder row, in the panel.
    ///
    /// Still a read, which is the only reason this is allowed to exist at
    /// all: going into a folder adds no verb the shelf did not already have,
    /// so the one-folder-written rule is untouched. See decision 0003, which
    /// ruled the other way and says what would have to change.
    ///
    /// The sandbox needs nothing new either. A security-scoped grant covers
    /// the folder's whole subtree, so everything reachable this way was
    /// already reachable — it simply had nowhere to be shown.
    /// Opens a folder row where it stands, or closes it again.
    ///
    /// What space does to a folder, and what the triangle does. The list you
    /// were looking at stays exactly where it was and the folder's contents
    /// appear underneath it, indented — the Finder's list view, which is what
    /// makes this answerable without going anywhere.
    ///
    /// Two earlier shapes were wrong in the same way: navigating on space
    /// took the list away, and a card laid over the list covered it. Both
    /// answered "take me there" when the question was "what is in there".
    func toggleShelfFolder(_ row: ShelfRowItem) {
        guard row.isEnterable else { return }

        if row.isOpen { return shelf.close(row.url) }

        guard shelf.canOpen(row) else {
            shelfHandoff = shelf.tooDeepMessage(row)
            return
        }

        let url = row.url
        Task { @MainActor in
            let read = await Task.detached(priority: .userInitiated) {
                // Its own root: a folder opened in place is not somewhere you
                // went, so it has no trail and nowhere to climb to.
                ShelfReader.read(url, root: url)
            }.value
            shelf.open(url, showing: read)
        }
    }

    func collapseShelfFolders() {
        guard shelf.hasOpenFolders else { return }
        shelf.collapseAll()
    }

    func enterShelfFolder(_ entry: ShelfEntry) {
        guard entry.isEnterable, let folder = shelf.current else { return }
        descend(to: entry.url, under: folder.root)
    }

    /// Back up one level, stopping at the tab's own folder.
    ///
    /// `ShelfFolder.parent` is what refuses to go above the root, and it
    /// refuses in the engine where it is checked rather than here.
    func leaveShelfFolder() {
        guard let folder = shelf.current, let parent = folder.parent else { return }
        descend(to: parent, under: folder.root)
    }

    /// All the way back to the tab.
    func returnToShelfRoot() {
        guard let folder = shelf.current, !folder.isAtRoot else { return }
        descend(to: folder.root, under: folder.root)
    }

    private func descend(to url: URL, under root: URL) {
        // The picked row is in the folder you are leaving. Put down first, so
        // the footer is not describing a file that is no longer on screen —
        // and the peek goes with it, for the same reason.
        shelf.deselect()
        lastShelfRead = Date()
        Task { await list(url, under: root) }
    }

    // MARK: - Moving between them

    /// Lists a different folder — by a click on its tab, or by the pointer
    /// resting on one.
    ///
    /// The guard is what makes pointing affordable. Every hover along the tab
    /// row arrives here, and without it the folder already on screen would be
    /// read off the disk again each time the cursor passed over its own tab.
    func showShelfFolder(at index: Int) {
        guard shelf.shouldShow(folderAt: index) else { return }
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

    /// A click on a row: pick it, or open it if it completed a pair.
    ///
    /// One gesture does both, so nothing waits — see `ClickPair` for what the
    /// two-gesture version cost. `NSEvent.doubleClickInterval` is the
    /// person's own setting, read here at the platform edge and handed to the
    /// rule, which lives in the engine where it is checked.
    func clickShelfRow(_ row: ShelfRowItem) {
        let paired = shelfClicks.isSecond(row.id,
                                          at: Date(),
                                          within: NSEvent.doubleClickInterval)
        if paired {
            openShelfEntry(row.entry)
        } else {
            selectShelfEntry(row.id)
        }
    }

    func selectShelfEntry(_ id: String?) {
        guard shelf.selected != id else { return }
        shelf.select(id)
    }

    func deselectShelfEntry() {
        guard shelf.selected != nil else { return }
        shelf.deselect()
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

    /// Opens a row the way double-clicking it in the Finder would.
    ///
    /// Still not a write: handing a file to the application that owns it is
    /// what the Finder does, and Hoot does not touch the file either way.
    ///
    /// A folder is listed here rather than handed to the Finder. It used to
    /// be handed over, because the shelf showed folders and refused to go
    /// into them — decision 0003 says why, and now says why not. Right-click
    /// → Show in Finder is still the way out to the Finder.
    func openShelfEntry(_ entry: ShelfEntry) {
        if entry.isEnterable { return enterShelfFolder(entry) }

        guard entry.isOpenable else {
            // Safety rule 5. The row already says Hoot will not open this
            // one; handing it to `NSWorkspace` would have downloaded it,
            // which is the whole of what the rule is about. Revealing it in
            // the Finder still works, and there the download is the person's
            // own doing rather than a side effect of a double-click.
            shelfHandoff = "\(entry.name) is in iCloud and not downloaded"
            return
        }

        NSWorkspace.shared.open(entry.url)
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
