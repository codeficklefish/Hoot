import Foundation
import HootKit
// For the folder adapters. The suite links both modules; only the app
// target's views and controller are out of reach from here.
import HootPlatformMac

/// The notch HUD: where its panel goes, and what it decides to show.
///
/// This stage exists because of how the previous version of this surface
/// failed. It lived entirely in the app target, which nothing here can
/// import, so the app crash-looped all evening while 270 checks passed —
/// and a one-point seam against the bezel went unnoticed until someone
/// looked at the screen. The arithmetic and the state machine are in the
/// engine now precisely so they can be checked here.
func stageHUD(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    // MARK: - Where the panel goes

    print("\n[the HUD meets the camera housing]")

    // Measured from the window server on a real display in the original
    // implementation: a 1710pt-wide screen whose cutout spans 763→948.
    // These are the numbers a seam would show up in.
    let notch = NotchShape(height: 37, width: 185, centerX: 855.5)
    let screenTopY: Double = 1107

    check("the cutout is not where the screen's middle is",
          notch.centerX != 1710 / 2, "\(notch.centerX)")

    check("the panel is at least as wide as the cutout",
          HUDPlacement.minimumWidth(for: notch) == 187,
          "\(HUDPlacement.minimumWidth(for: notch))")

    let collapsed = HUDPlacement.frame(
        contentWidth: 120, contentHeight: 30, notch: notch, screenTopY: screenTopY
    )
    check("a narrow pill is widened to cover the cutout",
          collapsed.width == 187, "\(collapsed.width)")
    check("collapsed, its left edge lands at 762",
          collapsed.x == 762, "\(collapsed.x)")
    check("and its right edge at 949",
          collapsed.x + collapsed.width == 949, "\(collapsed.x + collapsed.width)")
    check("so it overlaps the cutout on both sides",
          collapsed.x < 763 && collapsed.x + collapsed.width > 948)

    // The cutout's centre sits on a half-point, so an odd bleed would put
    // the collapsed panel's edge on one too — and AppKit rounds a window
    // frame to whole points, which is how a half-point of desktop reopens
    // against the bezel. An even bleed is what keeps this exact.
    check("collapsed, it lands on whole points",
          collapsed.x == collapsed.x.rounded(), "\(collapsed.x)")
    check("which only holds because the bleed is even",
          HUDPlacement.bleed.truncatingRemainder(dividingBy: 2) == 0)

    check("its top edge is the top of the display",
          HUDPlacement.gapAboveTop(
            originY: collapsed.y, contentHeight: 30, screenTopY: screenTopY
          ) == 0)

    let expanded = HUDPlacement.frame(
        contentWidth: 320, contentHeight: 210, notch: notch, screenTopY: screenTopY
    )
    check("expanded, it keeps its own width", expanded.width == 320, "\(expanded.width)")
    check("and stays centred on the camera, not the screen",
          expanded.x + expanded.width / 2 == notch.centerX,
          "\(expanded.x + expanded.width / 2)")
    check("and still meets the top of the display",
          HUDPlacement.gapAboveTop(
            originY: expanded.y, contentHeight: 210, screenTopY: screenTopY
          ) == 0)

    // A display with no cutout has nothing to grow out of.
    check("a screen without a notch reports none", !NotchShape.none.hasNotch)
    check("and asks for no minimum width",
          HUDPlacement.minimumWidth(for: .none) == 0)

    // MARK: - Walking through the plan, one folder at a time

    print("\n[the resting bar says which folder it is showing]")

    // It used to be exactly the width of the cutout, which made it invisible
    // — and made the mark and the folder's name invisible with it, because
    // the camera housing was directly over both. Reaching past the cutout is
    // the whole point, and the arithmetic is worth pinning because it decides
    // how much usable menu bar the bar sits on top of.
    let shoulder = 88.0
    let resting = notch.width + shoulder * 2
    check("the resting bar clears the cutout on both sides",
          resting > notch.width, "\(resting) vs \(notch.width)")
    check("by exactly a shoulder each side",
          (resting - notch.width) / 2 == shoulder)
    check("and is still wide enough for the placement rule",
          resting >= HUDPlacement.minimumWidth(for: notch),
          "\(resting) vs \(HUDPlacement.minimumWidth(for: notch))")

    // Centred on the camera, so the shoulders are even and the bar still
    // continues out of the housing rather than hanging off one side of it.
    let restingFrame = HUDPlacement.frame(
        contentWidth: resting, contentHeight: 34,
        notch: notch, screenTopY: 1107)
    check("the bar stays centred on the camera",
          restingFrame.x + restingFrame.width / 2 == notch.centerX,
          "\(restingFrame.x + restingFrame.width / 2) vs \(notch.centerX)")
    check("and still meets the top of the display",
          HUDPlacement.gapAboveTop(originY: restingFrame.y,
                                   contentHeight: 34, screenTopY: 1107) == 0)

    print("\n[a list stops growing before the window does]")

    // The panel is sized from its content's fittingSize, so a list with no
    // definite height asks for a window as tall as the folder is long.
    check("an empty list takes no height",
          HUDPlacement.listHeight(rows: 0, rowHeight: 26, maxRows: 9) == 0)
    check("a short list is exactly its rows",
          HUDPlacement.listHeight(rows: 3, rowHeight: 26, maxRows: 9) == 78,
          "\(HUDPlacement.listHeight(rows: 3, rowHeight: 26, maxRows: 9))")
    check("a long one stops at the cap",
          HUDPlacement.listHeight(rows: 200, rowHeight: 26, maxRows: 9) == 234,
          "\(HUDPlacement.listHeight(rows: 200, rowHeight: 26, maxRows: 9))")
    check("and a negative count cannot make it negative",
          HUDPlacement.listHeight(rows: -5, rowHeight: 26, maxRows: 9) == 0)

    print("\n[scrolling a list is not paging between folders]")

    // The HUD's scroll monitor swallows what it takes. Once the panel holds a
    // list, swallowing a vertical scroll would leave it unable to scroll.
    check("a sideways flick is paging",
          SwipeTracker.isHorizontal(deltaX: 30, deltaY: 2))
    check("a scroll down the list is not",
          !SwipeTracker.isHorizontal(deltaX: 2, deltaY: 30))
    check("nor is one that only leans sideways",
          !SwipeTracker.isHorizontal(deltaX: 12, deltaY: 10),
          "12 across, 10 down — under the 1.4x bias")
    check("the rule is the one track() uses", {
        var tracker = SwipeTracker()
        return tracker.track(deltaX: 2, deltaY: 30, phase: .began) == nil
    }())

    print("\n[what counts as somebody's file]")

    // The name rules, asked without touching a disk. Directories are judged
    // separately, because whether a folder should be shown depends on who is
    // asking: the organizer never touches one, the shelf lists them.
    func junk(_ name: String, size: Int = 1024) -> Bool {
        FileAnalyzer.isJunk(URL(fileURLWithPath: "/tmp/\(name)"), fileSize: size)
    }

    check("a dotfile is not somebody's file", junk(".DS_Store"))
    check("nor is an Office lock file", junk("~$Report.docx"))
    check("nor a half-finished download", junk("Xcode.dmg.crdownload"))
    check("nor a blank name with nothing in it", junk(" .png", size: 0))
    check("but a blank name with real content is kept",
          !junk(" .png", size: 4096))
    check("and an ordinary file is left alone", !junk("invoice_march.pdf"))

    check("a directory is ignored when files are what is wanted",
          FileAnalyzer.isIgnored(URL(fileURLWithPath: "/tmp/Receipts"),
                                 isDirectory: true, fileSize: 0))
    check("but it is not junk, so a shelf may still list it",
          !junk("Receipts", size: 0))

    print("\n[how long ago, in a column and in a sentence]")

    // Both forms against one fixed instant: read against the real clock they
    // change their answers as the evening wears on.
    var stamp = DateComponents()
    stamp.year = 2026; stamp.month = 9; stamp.day = 15
    stamp.hour = 22; stamp.minute = 0
    guard let anchorNow = Calendar.current.date(from: stamp) else {
        check("fixed clock", false); return
    }
    func ago(_ minutes: Double) -> Date { anchorNow.addingTimeInterval(-minutes * 60) }

    check("minutes read as minutes",
          RelativeAge.label(of: ago(22), now: anchorNow) == "22m",
          RelativeAge.label(of: ago(22), now: anchorNow))
    check("and as a phrase they gain an 'ago'",
          RelativeAge.since(ago(22), now: anchorNow) == "22m ago",
          RelativeAge.since(ago(22), now: anchorNow))
    check("hours the same",
          RelativeAge.since(ago(240), now: anchorNow) == "4h ago",
          RelativeAge.since(ago(240), now: anchorNow))
    // "Yest. ago" is not English, which is why the two forms are separate
    // functions rather than one with a suffix stuck on the end.
    check("yesterday is a word, not a count",
          RelativeAge.since(ago(60 * 26), now: anchorNow) == "yesterday",
          RelativeAge.since(ago(60 * 26), now: anchorNow))
    check("while the column still abbreviates it",
          RelativeAge.label(of: ago(60 * 26), now: anchorNow) == "Yest.",
          RelativeAge.label(of: ago(60 * 26), now: anchorNow))
    check("older than that counts days",
          RelativeAge.since(ago(60 * 24 * 3), now: anchorNow) == "3d ago",
          RelativeAge.since(ago(60 * 24 * 3), now: anchorNow))
    // 46 and a half hours: 23:30 two nights ago, which arithmetic that counts
    // hours and divides by 24 calls yesterday. Sunday night is not yesterday
    // on a Tuesday, and this is the case the calendar rule exists for. Note
    // that 46 hours exactly *is* yesterday — the boundary is the day, not
    // the elapsed time, which is exactly what makes it worth a check.
    check("the night before last is not yesterday",
          RelativeAge.label(of: ago(46.5 * 60), now: anchorNow) == "2d",
          RelativeAge.label(of: ago(46.5 * 60), now: anchorNow))
    check("while 46 hours still is",
          RelativeAge.label(of: ago(46 * 60), now: anchorNow) == "Yest.",
          RelativeAge.label(of: ago(46 * 60), now: anchorNow))
    check("a date in the future does not go negative",
          RelativeAge.since(anchorNow.addingTimeInterval(600), now: anchorNow) == "just now")
    check("the clock time is zero-padded",
          RelativeAge.clockTime(of: ago(60 * 13 + 55)) == "08:05",
          RelativeAge.clockTime(of: ago(60 * 13 + 55)))

    print("\n[several folders, each remembered on its own]")

    // Security-scoped bookmarks are a sandbox feature and this binary is not
    // sandboxed, so what can be checked here is the list bookkeeping rather
    // than the encoding. Probed rather than assumed: if bookmarking does work
    // outside the sandbox on this OS, the round trip is checked too.
    let suite = "hoot.verification.shelf"
    guard let shelfDefaults = UserDefaults(suiteName: suite) else {
        check("shelf defaults", false); return
    }
    shelfDefaults.removePersistentDomain(forName: suite)

    let shelfRoot = sandbox.appending(path: "shelf-folders")
    let alpha = shelfRoot.appending(path: "Alpha")
    let beta = shelfRoot.appending(path: "Beta")
    for dir in [alpha, beta] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    let shelfAccess = ShelfFolderAccess(defaults: shelfDefaults)
    check("nothing remembered yet", shelfAccess.restoreAll().folders.isEmpty)
    check("and nothing was dropped to get there", shelfAccess.restoreAll().dropped == 0)

    let addedAlpha = shelfAccess.remember(alpha)
    check("a folder new to the list is added", addedAlpha)
    check("the same folder again is refused", !shelfAccess.remember(alpha))
    // The spelling it is asked about is not the spelling a bookmark comes
    // back as: /tmp is a symlink to /private/tmp, and a resolved folder URL
    // carries a trailing slash. Both have to name the same folder.
    check("however it is spelled",
          !shelfAccess.remember(URL(fileURLWithPath: alpha.path + "/")))

    // Everything past this point needs the bookmark to have survived being
    // written and read back, which is the part the sandbox owns.
    let bookmarksWork = !shelfAccess.restoreAll().folders.isEmpty
    if bookmarksWork {
        shelfAccess.remember(beta)
        let restored = shelfAccess.restoreAll()
        check("both folders come back", restored.folders.count == 2,
              "\(restored.folders.map(\.lastPathComponent))")
        check("in the order they were added",
              restored.folders.first?.lastPathComponent == "Alpha",
              restored.folders.first?.lastPathComponent ?? "nil")
        check("none of them was dropped", restored.dropped == 0)

        shelfAccess.forget(alpha)
        let afterForget = shelfAccess.restoreAll()
        check("forgetting one leaves the rest",
              afterForget.folders.map(\.lastPathComponent) == ["Beta"],
              "\(afterForget.folders.map(\.lastPathComponent))")
    } else {
        print("  ....  bookmark round trip not checkable: "
            + "security-scoped bookmarks need the sandbox, and this binary has none")
    }
    shelfDefaults.removePersistentDomain(forName: suite)

    print("\n[a folder, read as the notch shows it]")

    let shelfDir = sandbox.appending(path: "shelf-read")
    let nested = shelfDir.appending(path: "Receipts")
    try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    for child in ["a.pdf", "b.pdf", "c.pdf"] {
        try? Data("x".utf8).write(to: nested.appending(path: child))
    }

    // Written oldest first, then stamped, so "newest first" is a claim about
    // the dates rather than about the order they happen to be listed in.
    let made: [(String, Double, Int)] = [
        ("invoice_march.pdf", 4, 2_400_000),
        ("photo.png", 90, 800_000),
        ("notes.txt", 60 * 26, 400)
    ]
    for (name, minutes, size) in made {
        let url = shelfDir.appending(path: name)
        try? Data(repeating: 0x41, count: size).write(to: url)
        let when = anchorNow.addingTimeInterval(-minutes * 60)
        try? FileManager.default.setAttributes(
            [.creationDate: when, .modificationDate: when], ofItemAtPath: url.path)
    }
    // Junk, which must not be listed.
    for junkName in [".DS_Store", "~$invoice_march.docx", "Xcode.dmg.crdownload"] {
        try? Data("x".utf8).write(to: shelfDir.appending(path: junkName))
    }

    let read = ShelfReader.read(shelfDir)
    check("the folder was readable", read.state == .listed, "\(read.state)")
    check("junk is not somebody's file", read.entries.count == 4,
          "\(read.entries.map(\.name).sorted())")
    check("a sub-folder is listed, where the organizer would ignore it",
          read.entries.contains { $0.isFolder && $0.name == "Receipts" })
    check("and it is measured in things, not bytes",
          read.entries.first { $0.isFolder }?.sizeLabel == "3 items",
          read.entries.first { $0.isFolder }?.sizeLabel ?? "nil")
    check("the header counts both kinds", read.accessory == "3 files · 1 folder",
          read.accessory)

    // The check that keeps the panel from redrawing under the pointer: an
    // unchanged folder read twice has to compare equal, or every refresh
    // publishes a new value and the list flickers.
    check("reading it again gives the same value", ShelfReader.read(shelfDir) == read)

    check("an empty folder says so, and is not an error", {
        let bare = sandbox.appending(path: "shelf-empty")
        try? FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let folder = ShelfReader.read(bare)
        return folder.state == .empty && folder.emptyMessage.contains("Nothing in")
    }())
    check("a folder that is not there is told apart from an empty one", {
        let gone = ShelfReader.read(sandbox.appending(path: "shelf-not-here"))
        return gone.state == .unavailable && gone.emptyMessage.contains("not available")
    }())

    print("\n[the order a folder is read in]")

    var shelf = FileShelf(folders: [read])
    check("newest first by default",
          shelf.rows.map(\.name) == ["Receipts", "invoice_march.pdf", "photo.png", "notes.txt"],
          "\(shelf.rows.map(\.name))")

    shelf.sort = .name
    check("by name, folders still lead",
          shelf.rows.first?.name == "Receipts", shelf.rows.first?.name ?? "nil")
    check("and the files are alphabetical",
          shelf.rows.dropFirst().map(\.name) == ["invoice_march.pdf", "notes.txt", "photo.png"],
          "\(shelf.rows.dropFirst().map(\.name))")

    shelf.sort = .size
    check("by size, largest first",
          shelf.rows.dropFirst().map(\.name) == ["invoice_march.pdf", "photo.png", "notes.txt"],
          "\(shelf.rows.dropFirst().map(\.name))")

    check("the sort control cycles", FileShelf.SortOrder.added.next == .name
            && FileShelf.SortOrder.name.next == .size
            && FileShelf.SortOrder.size.next == .added)
    check("and names itself", FileShelf.SortOrder.added.label == "Date added")

    print("\n[what the notch prints about a shelf]")

    shelf.sort = .added
    check("the collapsed bar names the folder, and counts nothing",
          shelf.pillText == "shelf-read", shelf.pillText)
    check("the list stops growing at nine rows",
          shelf.listHeight == 4 * 26, "\(shelf.listHeight)")
    check("and a long folder is capped there", {
        let many = (0..<40).map {
            ShelfEntry(url: shelfDir.appending(path: "f\($0)"), symbolName: "doc",
                       isFolder: false, byteCount: 1, childCount: 0,
                       sortDate: anchorNow, isCloudPlaceholder: false)
        }
        let long = FileShelf(folders: [ShelfFolder(root: shelfDir, state: .listed, entries: many)])
        return long.rows.count == 40 && long.listHeight == 234
    }())

    check("nothing is picked to begin with", shelf.selectionDetail(now: anchorNow) == nil)
    let firstFile = shelf.rows.first { !$0.isFolder }!
    shelf.select(firstFile.id)
    check("a picked file says its size and when it came",
          shelf.selectionDetail(now: anchorNow) == "2.4 MB · added 4m ago",
          shelf.selectionDetail(now: anchorNow) ?? "nil")
    check("and the reveal button changes what it offers",
          shelf.revealLabel == "Show in Finder", shelf.revealLabel)
    // Clicking a selected row leaves it selected, as the Finder does. It also
    // has to: a double-click is two clicks, and a toggle would put the row
    // down again on its way to opening the file.
    shelf.select(firstFile.id)
    check("picking it again leaves it picked", shelf.pickedEntry?.id == firstFile.id)
    shelf.deselect()
    check("escape is what puts it down", shelf.pickedEntry == nil)
    check("and the button goes back to the folder",
          shelf.revealLabel == "Open folder", shelf.revealLabel)

    // The organizer's one appearance here. A folder with no plan has no
    // button at all, rather than a button reading zero.
    check("handing a folder over says so", shelf.revealMessage == "Opened shelf-read in the Finder",
          shelf.revealMessage)
    check("and names the file when one is picked", {
        var picked = shelf
        picked.select(picked.rows.first { !$0.isFolder }!.id)
        return picked.revealMessage == "Revealed invoice_march.pdf in the Finder"
    }(), {
        var picked = shelf
        picked.select(picked.rows.first { !$0.isFolder }!.id)
        return picked.revealMessage
    }())
    // The case that reads "1 files" if nobody tries it.
    check("one file is a file", shelf.tidyMessage(untidy: 1).contains("1 file in"),
          shelf.tidyMessage(untidy: 1))
    check("and several are files", shelf.tidyMessage(untidy: 4).contains("4 files in"),
          shelf.tidyMessage(untidy: 4))

    check("no tidying to offer means no button", shelf.tidyLabel(untidy: 0) == nil)
    check("and otherwise it counts", shelf.tidyLabel(untidy: 5) == "Tidy 5",
          shelf.tidyLabel(untidy: 5) ?? "nil")

    print("\n[keeping the tabs straight]")

    func folderNamed(_ name: String) -> ShelfFolder {
        ShelfFolder(root: sandbox.appending(path: name), state: .empty, entries: [])
    }
    var tabs = FileShelf()
    // It used to send you to Settings. The standard folders are offered at
    // the notch itself now, so the message points at what is on screen.
    check("an empty shelf points at the control beside it",
          tabs.isEmpty && tabs.emptyMessage.contains("+"),
          tabs.emptyMessage)
    check("and it knows there is room for more", tabs.hasRoom)
    check("a shelf holds three folders, so three names stay readable",
          FileShelf.maxFolders == 3, "\(FileShelf.maxFolders)")
    for index in 0..<FileShelf.maxFolders {
        check("folder \(index + 1) is added", tabs.add(folderNamed("F\(index)")))
    }
    check("one past the cap is refused", !tabs.add(folderNamed("F99")))
    check("and a full shelf says so rather than hiding the control",
          !tabs.hasRoom)
    check("and so is one already there", !tabs.add(folderNamed("F0")))

    let last = FileShelf.maxFolders - 1
    tabs.show(folderAt: last)
    check("paging lands where it was asked", tabs.showing == last, "\(tabs.showing)")
    tabs.showNext()
    check("and cannot walk off the end", tabs.showing == last, "\(tabs.showing)")
    tabs.show(folderAt: 0)
    tabs.showPrevious()
    check("nor off the front", tabs.showing == 0, "\(tabs.showing)")

    print("\n[pointing at a tab is enough to list it]")

    // The tab row is also the way to the `+` beside it, so the cursor crosses
    // every tab on a trip somebody did not mean as a folder change. What makes
    // that affordable is the shelf refusing the tab it is already on, and the
    // panel waiting a moment before it believes any of the others.
    tabs.show(folderAt: 0)
    check("pointing at another folder's tab shows it", tabs.shouldShow(folderAt: 1))
    check("pointing at the one already showing does nothing",
          !tabs.shouldShow(folderAt: 0))
    check("and a tab that is not there is refused",
          !tabs.shouldShow(folderAt: 99) && !tabs.shouldShow(folderAt: -1))

    // A picked row and its folder go together. Crossing your own tab must not
    // put the row down — which it did, until `show` started asking first.
    var picky = FileShelf(folders: [folderNamed("A"), folderNamed("B")])
    picky.select("kept")
    picky.show(folderAt: 0)
    check("the folder you are on keeps the row you picked",
          picky.selected == "kept", picky.selected ?? "nil")
    picky.show(folderAt: 1)
    check("and a different folder cannot, so the row goes down",
          picky.selected == nil, picky.selected ?? "nil")

    check("the dwell is a pause, not a wait",
          FileShelf.hoverDwell > 0 && FileShelf.hoverDwell <= 0.3,
          "\(FileShelf.hoverDwell)")

    tabs.show(folderAt: last)
    tabs.remove(sandbox.appending(path: "F\(last)"))
    check("removing the folder being shown clamps rather than jumping home",
          tabs.showing == last - 1, "\(tabs.showing)")
    check("and the rest are still there", tabs.folders.count == last,
          "\(tabs.folders.count)")

    print("\n[the same folder, however it is spelled]")

    // Three things ask this now — the bookmark store, the shelf's tab list,
    // and the check for whether a shelf folder is also the one being
    // organized — so the rule is written once and checked here.
    let identityDir = sandbox.appending(path: "identity")
    try? FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
    check("a trailing slash names the same folder",
          FolderIdentity.same(identityDir, URL(fileURLWithPath: identityDir.path + "/")))
    check("and so does a path through a symlink", {
        let link = sandbox.appending(path: "identity-link")
        try? FileManager.default.removeItem(at: link)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: identityDir)
        return FolderIdentity.same(identityDir, link)
    }())
    check("but a different folder is a different folder",
          !FolderIdentity.same(identityDir, sandbox.appending(path: "identity-other")))

    print("\n[going into a folder, and coming back out]")

    // Decision 0003 ruled the other way: folders were listed and not
    // navigable, "one line to reverse if it proves wrong". It proved wrong.
    // What did not change is the reason the shelf may have several folders —
    // going in is still a read, and there is still no verb here that writes.
    // Its own tree rather than the one above, which earlier checks count.
    let nest = sandbox.appending(path: "nest")
    let inner = nest.appending(path: "inner")
    let deeper = inner.appending(path: "deeper")
    try? FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: deeper.appending(path: "buried.txt").path,
                                   contents: Data("x".utf8))

    let atRoot = ShelfReader.read(nest)
    check("a tab starts at its own folder", atRoot.isAtRoot)
    check("so there is nowhere above it to go", atRoot.parent == nil)
    check("and no trail to print", atRoot.trailLabel.isEmpty, atRoot.trailLabel)

    let inside = ShelfReader.read(inner, root: nest)
    check("going in keeps the tab's identity", inside.id == atRoot.id, inside.id)
    check("so the tab is still named after what was added",
          inside.name == atRoot.name, inside.name)
    check("while the panel names what is on screen",
          inside.listingName == "inner", inside.listingName)
    check("the trail says how far down you are",
          inside.trailLabel == "\(atRoot.name) / inner", inside.trailLabel)
    check("and there is somewhere above to go",
          inside.parent.map { FolderIdentity.same($0, nest) } == true)

    let deep = ShelfReader.read(deeper, root: nest)
    check("two levels down reads as two levels down",
          deep.trail == ["inner", "deeper"], "\(deep.trail)")
    check("and the way back is one level, not all of it",
          deep.parent.map { FolderIdentity.same($0, inner) } == true)

    // The tab is what the sandbox granted. Its parent was not, so climbing
    // has to stop there however it is asked.
    let escapee = ShelfReader.read(sandbox, root: nest)
    check("a listing outside its own tab claims no trail", escapee.isAtRoot)
    check("so nothing offers to climb out of the granted folder",
          escapee.parent == nil)

    // Replacing works on the root, so a descended folder still lands in its
    // own tab rather than being dropped for not matching.
    var descending = FileShelf(folders: [ShelfFolder(root: nest, state: .empty, entries: [])])
    descending.replace(inside)
    check("a folder read from inside still lands in its tab",
          descending.current?.listingName == "inner",
          descending.current?.listingName ?? "nil")
    check("and the empty message names what is on screen, not the tab", {
        let emptyInner = ShelfFolder(root: nest, url: inner, state: .empty, entries: [])
        return emptyInner.emptyMessage == "Nothing in inner."
    }(), ShelfFolder(root: nest, url: inner, state: .empty, entries: []).emptyMessage)

    // Taking the tab off the shelf is about the tab, whatever is listed.
    descending.remove(nest)
    check("removing the tab works from inside it", descending.isEmpty)

    print("\n[opening a folder where it stands]")

    // Two earlier shapes were wrong the same way. Space navigated, and then
    // space laid a card over the list. Both took away the thing you were
    // looking at in order to answer a question you asked *while* looking at
    // it. The list opens in place now, as the Finder's does.
    let treeDir = sandbox.appending(path: "tree")
    let branch = treeDir.appending(path: "branch")
    try? FileManager.default.createDirectory(at: branch, withIntermediateDirectories: true)
    for name in ["leaf-a.txt", "leaf-b.txt"] {
        FileManager.default.createFile(atPath: branch.appending(path: name).path,
                                       contents: Data("x".utf8))
    }
    FileManager.default.createFile(atPath: treeDir.appending(path: "top.txt").path,
                                   contents: Data("x".utf8))

    var tree = FileShelf(folders: [ShelfReader.read(treeDir)])
    // By name, because the two leaves were written in the same instant and
    // "newest first" between them is a coin toss.
    tree.sort = .name
    check("closed, the list is just what is in the folder",
          tree.rows.map(\.name) == ["branch", "top.txt"], "\(tree.rows.map(\.name))")
    check("a folder row offers a triangle",
          tree.rows.first?.disclosure == .closed, "\(tree.rows.first?.disclosure as Any)")
    check("and a file does not",
          tree.rows.last?.disclosure == .plain, "\(tree.rows.last?.disclosure as Any)")
    check("nothing is open to begin with", !tree.hasOpenFolders)

    let branchRow = tree.rows.first!
    tree.open(branchRow.url, showing: ShelfReader.read(branch, root: branch))
    check("opening one splices its contents in under it",
          tree.rows.map(\.name) == ["branch", "leaf-a.txt", "leaf-b.txt", "top.txt"],
          "\(tree.rows.map(\.name))")
    check("the rows inside it are one level in",
          tree.rows.map(\.depth) == [0, 1, 1, 0], "\(tree.rows.map(\.depth))")
    check("and the folder now points down", tree.rows.first?.disclosure == .open)
    check("the list knows something is open", tree.hasOpenFolders)

    // The panel has to grow for them, or the folder would open into rows
    // nobody can see.
    check("the panel counts the opened rows in its height",
          tree.listHeight == 4 * FileShelf.rowHeight, "\(tree.listHeight)")

    check("closing it puts the list back",
          { var t = tree; t.close(branchRow.url)
            return t.rows.map(\.name) == ["branch", "top.txt"] && !t.hasOpenFolders }())

    // A folder closed while holding open folders inside it must not remember
    // them: re-opening it would silently re-open three more, showing whatever
    // was on the disk minutes ago.
    check("closing a folder closes what was open inside it", {
        var t = tree
        let leafFolder = ShelfFolder(root: branch, state: .empty, entries: [])
        t.open(branch.appending(path: "deeper"), showing: leafFolder)
        t.close(branchRow.url)
        return t.open.isEmpty
    }(), "row \(branchRow.key) vs folder \(FolderIdentity.key(branch))")

    // But a sibling whose path merely starts with the same characters is a
    // different folder, and stays open.
    check("a folder that only shares a prefix is left alone", {
        var t = FileShelf(folders: [ShelfReader.read(treeDir)])
        let twin = treeDir.appending(path: "branch-two")
        t.open(branch, showing: ShelfFolder(root: branch, state: .empty, entries: []))
        t.open(twin, showing: ShelfFolder(root: twin, state: .empty, entries: []))
        t.close(branch)
        return t.open == [FolderIdentity.key(twin)]
    }())

    check("changing tab closes everything that was open", {
        var t = FileShelf(folders: [ShelfReader.read(treeDir),
                                    ShelfFolder(root: sandbox, state: .empty, entries: [])])
        t.open(branch, showing: ShelfFolder(root: branch, state: .empty, entries: []))
        t.show(folderAt: 1)
        return !t.hasOpenFolders
    }())

    // Indentation costs width out of a 420pt panel, so the list stops going
    // in and says the row is somewhere to go instead.
    check("the list opens four levels and no further",
          FileShelf.maxDepth == 4, "\(FileShelf.maxDepth)")
    check("a row near the top may be opened where it stands",
          tree.canOpen(branchRow))
    check("one at the bottom of that may not", {
        let deep = ShelfRowItem(entry: branchRow.entry,
                                depth: FileShelf.maxDepth - 1, disclosure: .closed)
        return !tree.canOpen(deep)
    }())
    check("and is told what to do instead", {
        let deep = ShelfRowItem(entry: branchRow.entry,
                                depth: FileShelf.maxDepth - 1, disclosure: .closed)
        return tree.tooDeepMessage(deep).contains("double-click")
    }())
    check("a file is never openable in place, however shallow", {
        let file = tree.rows.last!
        return !tree.canOpen(file)
    }())

    // The bug this caught, kept as its own check. The reader hands back
    // `/private/var/...` where a path built by hand says `/var/...`, so a
    // folder closed under one spelling stayed open under the other.
    check("a folder is closed however its path is spelled", {
        var t = tree
        let spelled = URL(fileURLWithPath: "/private" + branchRow.url.path)
        let other = FileManager.default.fileExists(atPath: spelled.path) ? spelled : branchRow.url
        t.close(other)
        return !t.hasOpenFolders
    }())

    // A late read must not resurrect a folder somebody just closed.
    check("contents arriving after a close are dropped", {
        var t = tree
        t.close(branchRow.url)
        t.refreshOpen([branchRow.key: ShelfReader.read(branch, root: branch)])
        return !t.hasOpenFolders && t.rows.count == 2
    }())

    print("\n[a file in the cloud is still not opened]")

    // Safety rule 5's first appearance on a surface that is not the organizer:
    // previewing a placeholder would start a download nobody asked for.
    let placeholder = ShelfEntry(
        url: shelfDir.appending(path: "far-away.pdf"), symbolName: "doc",
        isFolder: false, byteCount: 0, childCount: 0,
        sortDate: anchorNow, isCloudPlaceholder: true)
    check("the row knows before anything offers to open it",
          placeholder.isCloudPlaceholder)
    check("and nothing will preview it", !placeholder.isPreviewable)
    // The gap this closed: a double-click used to go straight to NSWorkspace
    // whatever the row was, so the one gesture the tooltip promised was safe
    // would have downloaded the file.
    check("nor will a double-click open it", !placeholder.isOpenable)
    check("and it is not somewhere to go either", !placeholder.isEnterable)

    let dir = ShelfEntry(url: shelfDir, symbolName: "folder", isFolder: true,
                         byteCount: 0, childCount: 3, sortDate: anchorNow,
                         isCloudPlaceholder: false)
    check("a folder is not previewed — it has contents, not a preview",
          !dir.isPreviewable)
    check("it is somewhere to go instead", dir.isEnterable)

    // A folder in the cloud is still a folder, and still not touched.
    check("a folder that is not downloaded is neither", {
        let far = ShelfEntry(url: shelfDir.appending(path: "away"), symbolName: "folder",
                             isFolder: true, byteCount: 0, childCount: 0,
                             sortDate: anchorNow, isCloudPlaceholder: true)
        return !far.isEnterable && !far.isPreviewable && !far.isOpenable
    }())

    check("but an ordinary file on this disk may be looked inside",
          shelf.rows.first { !$0.isFolder }?.isPreviewable == true)
    check("and an ordinary file does not",
          !(shelf.rows.first { !$0.isFolder }?.isCloudPlaceholder ?? true))

    print("\n[what counts as a swipe]")

    var tracker = SwipeTracker()
    check("a nudge is not a swipe",
          tracker.track(deltaX: -8, deltaY: 0, phase: .began) == nil)
    check("until it has travelled far enough",
          tracker.track(deltaX: -22, deltaY: 0, phase: .changed) == .next)
    check("and then only once, however far it carries on",
          tracker.track(deltaX: -40, deltaY: 0, phase: .changed) == nil)

    tracker = SwipeTracker()
    check("the other way pages back",
          tracker.track(deltaX: 30, deltaY: 0, phase: .began) == .previous)

    tracker = SwipeTracker()
    check("a scroll down the panel is not a swipe across it",
          tracker.track(deltaX: 30, deltaY: 40, phase: .began) == nil)
    check("nor is one that only leans sideways",
          tracker.track(deltaX: 30, deltaY: 25, phase: .changed) == nil)

    tracker = SwipeTracker()
    _ = tracker.track(deltaX: -30, deltaY: 0, phase: .began)
    _ = tracker.track(deltaX: 0, deltaY: 0, phase: .ended)
    check("a fresh gesture can page again",
          tracker.track(deltaX: -30, deltaY: 0, phase: .began) == .next)

    // MARK: - One folder, one set of numbers
    //
    // The popover, the review window and the HUD all describe the same
    // folder, and they used to disagree: the popover counted every file it
    // had found and labelled each with the classifier's category, so files
    // the plan had decided to leave alone appeared under a destination as
    // though they were about to move. All three read the plan now.

    print("\n[every surface counts the same folder]")

    let countingDir = sandbox.appending(path: "counting")
    try? FileManager.default.createDirectory(at: countingDir, withIntermediateDirectories: true)

    func plannedFile(_ name: String) -> FileItem {
        let url = countingDir.appending(path: name)
        try? Data("x".utf8).write(to: url)
        return FileItem(url: url)!
    }

    func move(_ file: FileItem, to folder: String, approved: Bool = true) -> PlannedMove {
        PlannedMove(
            file: file,
            classification: ClassificationResult(
                fileID: file.id, category: folder, project: nil,
                suggestedFolder: folder, suggestedName: file.filename,
                confidence: 0.8, reason: ""
            ),
            destinationFolder: folder, roleSubfolder: nil,
            destinationName: file.filename, isApproved: approved
        )
    }

    let counted = OrganizationPlan(
        root: countingDir,
        groups: [
            PlannedGroup(name: "Flood Evacuation Routing System", proposedName: "", rationale: "",
                         moves: [move(plannedFile("a.pdf"), to: "Flood"),
                                 move(plannedFile("b.pdf"), to: "Flood")]),
            PlannedGroup(name: "Finance", proposedName: "", rationale: "",
                         moves: [move(plannedFile("c.pdf"), to: "Finance")])
        ],
        skipped: [
            (plannedFile("d.bin"), "unrecognized"),
            (plannedFile("e.bin"), "unrecognized"),
            (plannedFile("f.bin"), "unrecognized")
        ]
    )

    let chips: [OrganizationPlan.WaitingEntry] = counted.waiting
    let chipLabels: [String] = chips.map(\.label)
    let chipTotal: Int = chips.reduce(0) { $0 + $1.count }
    let folderTotal: Int = counted.allMoves.count + counted.skipped.count

    check("one entry per destination, plus the files left alone",
          chips.count == 3, "\(chipLabels)")
    check("the destinations are the plan's folders, not the classifier's categories",
          chips.first?.label == "Flood Evacuation Routing System",
          chips.first?.label ?? "nil")
    check("counted by the moves that would happen",
          chips.first?.count == 2, "\(chips.first?.count ?? -1)")
    check("what will not be touched is said outright",
          chips.last == OrganizationPlan.WaitingEntry(label: "Left alone", count: 3),
          "\(String(describing: chips.last))")
    check("the chips add up to the folder",
          chipTotal == folderTotal, "\(chipTotal) vs \(folderTotal)")
    check("and the review count is what the review window will show",
          counted.allMoves.count == 3, "\(counted.allMoves.count)")

    let allUnticked = OrganizationPlan(
        root: countingDir,
        groups: [PlannedGroup(name: "Finance", proposedName: "", rationale: "",
                              moves: [move(plannedFile("g.pdf"), to: "Finance", approved: false)])],
        skipped: []
    )
    check("a folder nobody is taking drops out of the summary",
          allUnticked.waiting.isEmpty, "\(allUnticked.waiting.map(\.label))")

    // MARK: - Whose confidence is being quoted

    print("\n[the panel never quotes the model on itself]")

    let subject = plannedFile("h.pdf")
    let rated = RuleBasedClassifier().classify(subject, excerpt: nil)

    func rationale(for source: DetectedProject.Source) -> String {
        OrganizationPlanner().makePlan(
            root: countingDir,
            detectedProjects: [DetectedProject(
                name: "Flood Evacuation Routing System", files: [subject],
                rationale: "These files share a routing study.",
                confidence: 0.95, source: source
            )],
            ungrouped: [],
            classifications: [subject.id: rated]
        ).groups.first?.rationale ?? ""
    }

    let fromModel = rationale(for: .ai(providerName: "Apple Intelligence (on-device)"))
    check("a model's reading says where it was read",
          fromModel.contains("Apple Intelligence (on-device)"), fromModel)
    check("and never how sure the model said it was",
          !fromModel.contains("%") && !fromModel.contains("confident"), fromModel)

    // The rules' number is measured overlap between the filenames — a fact
    // about the files rather than an opinion — so it stays.
    let fromRules = rationale(for: .rules)
    check("a measured match still carries its number",
          fromRules.contains("95% match"), fromRules)

    // MARK: - Captions that tell the tiles apart
}
