import Foundation
import HootKit

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

    print("\n[the HUD files one folder at a time]")

    func file(_ name: String, newName: String? = nil) -> TidyFile {
        TidyFile(moveID: UUID(), currentName: name, proposedName: newName, kindSymbol: "doc")
    }

    let opaque = file("12312312312312.docx", newName: "Patrick Hans Daguno — resume.docx")
    let dashes = file("------.pdf", newName: "Patrick Hans Daguno — resume.pdf")
    let plain = file("notes-final.pdf")

    let resume = TidyGroup(
        name: "Resume and Contact Information",
        reason: "Each one holds a name, a phone number and a work history.",
        files: [opaque, dashes]
    )
    let documents = TidyGroup(
        name: "Documents",
        reason: "No clear evidence of a shared subject. Sorted by file type instead.",
        files: [plain]
    )

    var flow = TidyFlow(groups: [resume, documents], isRenaming: true)

    check("an empty plan gives the HUD nothing to show",
          TidyFlow(groups: [], isRenaming: true).stage == .idle)

    check("the pill counts every file, not every folder",
          flow.pillText == "3 files could be sorted and named", flow.pillText)
    check("and says it in the singular when there is one",
          TidyFlow(groups: [documents], isRenaming: true).pillText
            == "1 file could be sorted and named")

    guard case .reviewing(let first) = flow.stage else {
        check("the first group is up for review", false); return
    }
    check("the first group is up for review", first.group.name == resume.name)
    check("the step is counted from one", first.stepLabel == "1 of 2", first.stepLabel)
    check("every file starts picked", first.pickedLabel == "2/2", first.pickedLabel)
    check("the button says what it will do, counted",
          first.primaryLabel == "Move & Rename 2", first.primaryLabel)

    // ---- what each row says ----
    check("a renamed row leads with the new name",
          first.rows[0].shownName == "Patrick Hans Daguno — resume.docx")
    check("a folder that does have new names shows the column for them",
          first.showsProposedNames)
    check("and strikes out the one it replaces",
          first.rows[0].replacedName == "12312312312312.docx")
    check("with the word that explains the strike", first.rows[0].subLead == "was")

    // ---- the rename chip ----
    flow.isRenaming = false
    guard case .reviewing(let unrenamed) = flow.stage else {
        check("turning renaming off keeps the group", false); return
    }
    check("with renaming off the row keeps its own name",
          unrenamed.rows[0].shownName == "12312312312312.docx")
    check("and nothing is struck out", unrenamed.rows[0].replacedName == nil)
    check("the row says the name is being kept",
          unrenamed.rows[0].subLead == "keeps its name", unrenamed.rows[0].subLead)
    check("and the button drops the word rename",
          unrenamed.primaryLabel == "Move 2", unrenamed.primaryLabel)
    check("renaming nothing is counted as nothing", unrenamed.renamableCount == 0)
    flow.isRenaming = true

    // ---- a file with no name to suggest ----
    var single = TidyFlow(groups: [documents], isRenaming: true)
    guard case .reviewing(let lone) = single.stage else {
        check("a group of one is reviewable", false); return
    }
    check("a file Hoot could not name says so",
          lone.rows[0].subLead == "no clear name to suggest", lone.rows[0].subLead)
    check("and is not counted as a rename", lone.renamableCount == 0)

    // ---- unticking ----
    flow.toggle(opaque.moveID)
    guard case .reviewing(let dropped) = flow.stage else {
        check("unticking keeps the group", false); return
    }
    check("an unticked file is shown as dropped", dropped.rows[0].isKept == false)
    check("the count follows it", dropped.pickedLabel == "1/2", dropped.pickedLabel)
    check("and so does the button", dropped.primaryLabel == "Move & Rename 1")
    check("only the kept files would be filed", flow.keptFiles.count == 1)

    flow.toggle(opaque.moveID)
    check("and ticking it again puts it back", flow.keptFiles.count == 2)

    // Unticking everything must not offer to move nothing.
    flow.toggle(opaque.moveID)
    flow.toggle(dashes.moveID)
    guard case .reviewing(let empty) = flow.stage else {
        check("an empty group is still reviewable", false); return
    }
    check("with nothing picked the button says so",
          empty.primaryLabel == "Nothing selected", empty.primaryLabel)
    check("and refuses to be pressed", empty.canApply == false)
    flow.toggle(opaque.moveID)
    flow.toggle(dashes.moveID)

    // ---- advancing ----
    flow.recordApplied(movedFiles: 2, renamedFiles: 2)
    guard case .reviewing(let second) = flow.stage else {
        check("answering one group moves to the next", false); return
    }
    check("answering one group moves to the next", second.group.name == documents.name)
    check("and the step label follows", second.stepLabel == "2 of 2", second.stepLabel)

    flow.skip()
    guard case .finished(let summary) = flow.stage else {
        check("answering the last group finishes the walk", false); return
    }
    check("answering the last group finishes the walk", true)
    check("the summary counts what actually moved",
          summary.title == "2 files moved into 1 folder", summary.title)
    check("and what was renamed",
          summary.detail == "2 files were renamed too. Any move can be undone later.",
          summary.detail)
    check("a skipped group is not counted as a folder", summary.movedGroups == 1)

    // ---- the summary's other shapes ----
    check("one file reads in the singular",
          TidySummary(movedFiles: 1, movedGroups: 1, renamedFiles: 1).title
            == "1 file moved into 1 folder")
    check("one rename reads in the singular",
          TidySummary(movedFiles: 1, movedGroups: 1, renamedFiles: 1).detail
            == "1 file was renamed too. Any move can be undone later.")
    check("skipping everything says so",
          TidySummary(movedFiles: 0, movedGroups: 0, renamedFiles: 0).title
            == "Every file stayed where it was")
    check("renaming nothing says so too",
          TidySummary(movedFiles: 2, movedGroups: 1, renamedFiles: 0).detail
            == "Nothing was renamed. Any move can be undone later.")
    // Whatever happened, the way back is always on screen.
    for renamed in 0...2 {
        check("the summary always says it can be undone (\(renamed) renamed)",
              TidySummary(movedFiles: 2, movedGroups: 1, renamedFiles: renamed)
                .detail.contains("can be undone"))
    }

    // ---- undo puts the walk back to the start ----
    flow.restart()
    guard case .reviewing(let restarted) = flow.stage else {
        check("undo returns to the first group", false); return
    }
    check("undo returns to the first group", restarted.index == 0)
    check("with every file picked again", restarted.pickedLabel == "2/2")
    single.skip()
    check("a one-group walk finishes after one answer",
          { if case .finished = single.stage { return true }; return false }())

    // MARK: - Renaming in place is a move, and moves come back

    print("\n[a rename is a move that stays put]")

    let root = sandbox.appending(path: "hud-rename")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let original = root.appending(path: "32131231231.pdf")
    try? Data("boarding pass".utf8).write(to: original)

    guard let item = FileItem(url: original) else {
        check("the rename fixture exists", false)
        return
    }

    let classification = ClassificationResult(
        fileID: item.id,
        category: "Travel",
        project: nil,
        suggestedFolder: "Travel",
        suggestedName: "Delta boarding pass Manila.pdf",
        confidence: 0.9,
        reason: "Read from inside the file."
    )

    // The HUD renames where the file stands, so the destination folder is
    // the watched folder itself — an empty subpath. This is the one case the
    // organizer had never been asked for, and "" is exactly the kind of
    // value that turns into a path bug nobody notices until a file vanishes.
    let renameInPlace = PlannedMove(
        file: item,
        classification: classification,
        destinationFolder: "",
        roleSubfolder: nil,
        destinationName: "Delta boarding pass Manila.pdf",
        isApproved: true
    )

    let organizer = Organizer()
    let (batch, failures) = organizer.organize(
        OrganizationPlan(
            root: root,
            groups: [PlannedGroup(name: "", proposedName: "",
                                  rationale: "Renamed in place.", moves: [renameInPlace])],
            skipped: []
        )
    )

    check("renaming in place does not fail", failures.isEmpty,
          failures.map { $0.1.localizedDescription }.joined())
    check("it produces exactly one operation", batch.operations.count == 1)

    let renamed = root.appending(path: "Delta boarding pass Manila.pdf")
    check("the file is on disk under its new name",
          FileManager.default.fileExists(atPath: renamed.path))
    check("and is gone from under the old one",
          !FileManager.default.fileExists(atPath: original.path))
    check("it stayed in the folder it was already in",
          renamed.deletingLastPathComponent().path == root.path,
          renamed.deletingLastPathComponent().path)
    check("no folder was invented for it",
          (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count == 1)
    check("with the same contents",
          (try? Data(contentsOf: renamed)) == Data("boarding pass".utf8))

    let (restored, undoFailures) = organizer.undo(batch)
    check("undo puts the original name back",
          undoFailures.isEmpty && restored.count == 1)
    check("the file is called what it was called again",
          FileManager.default.fileExists(atPath: original.path))
    check("and leaves nothing behind under the new one",
          !FileManager.default.fileExists(atPath: renamed.path))

    // MARK: - What the notch layout prints
    //
    // The panel has two surfaces now — a folder at a time, and a tray saying
    // how much is waiting — and each has its own phrasing. Same reason as
    // every other label here: a count that reads "0 of 3 files" or an age
    // that reads "-4m" is only ever noticed by someone using it.

    print("\n[the notch's own labels]")

    // A fixed instant rather than `Date()`. These labels are relative to a
    // clock, and read against the real one they change their answers as the
    // evening wears on: a file "3h" old at eleven is "Yest." at one in the
    // morning, and the suite would start failing for no reason anybody
    // changed.
    var midEvening = DateComponents()
    midEvening.year = 2026; midEvening.month = 9; midEvening.day = 15
    midEvening.hour = 22; midEvening.minute = 0
    guard let now = Calendar.current.date(from: midEvening) else {
        check("the clock these labels are read against could be built", false); return
    }

    func waiting(_ name: String, minutesAgo: Double) -> TidyFile {
        TidyFile(moveID: UUID(), currentName: name, proposedName: nil,
                 kindSymbol: "doc", addedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    let trayFlow = TidyFlow(
        groups: [
            TidyGroup(name: "Receipts", reason: "Shared subject.", files: [
                waiting("a.pdf", minutesAgo: 4), waiting("b.pdf", minutesAgo: 9)
            ]),
            TidyGroup(name: "Documents", reason: "By type.", files: [
                waiting("c.pdf", minutesAgo: 200)
            ])
        ],
        isRenaming: true
    )

    check("the bar counts what is still waiting",
          trayFlow.pillCount == "3 new", trayFlow.pillCount)
    check("the tray says the same thing in words",
          trayFlow.waitingTitle == "3 files waiting", trayFlow.waitingTitle)
    check("and how many folders that is, oldest first",
          trayFlow.waitingDetail(now: now) == "2 folders suggested \u{00B7} oldest 3h",
          trayFlow.waitingDetail(now: now))
    check("an age under an hour is counted in minutes",
          TidyFile.age(of: now.addingTimeInterval(-240), now: now) == "4m",
          TidyFile.age(of: now.addingTimeInterval(-240), now: now))
    check("yesterday is named rather than counted",
          TidyFile.age(of: now.addingTimeInterval(-90_000), now: now) == "Yest.",
          TidyFile.age(of: now.addingTimeInterval(-90_000), now: now))
    check("a file with no date reports no age",
          TidyFile(moveID: UUID(), currentName: "x", proposedName: nil,
                   kindSymbol: "doc").ageLabel() == nil)

    guard case .reviewing(let notchStep) = trayFlow.stage else {
        check("the first group is reviewable", false); return
    }
    check("the folder's line counts its files in words",
          notchStep.pickedSentence == "2 of 2 files", notchStep.pickedSentence)
    check("the caption under the round action stays short",
          notchStep.actionLabel == "Move & name", notchStep.actionLabel)
    // Nothing in that folder has a new name to move to, so the column that
    // would carry one has nothing to say and does not appear.
    check("a folder with no new names hides the column for them",
          notchStep.showsProposedNames == false)

    var plainFlow = trayFlow
    plainFlow.isRenaming = false
    if case .reviewing(let plainStep) = plainFlow.stage {
        check("and drops the naming when naming is off",
              plainStep.actionLabel == "Move", plainStep.actionLabel)
    }

    var walked = trayFlow
    walked.recordApplied(movedFiles: 2, renamedFiles: 0)
    check("what has been filed is no longer waiting",
          walked.pillCount == "1 new", walked.pillCount)
    walked.skip()
    check("and once every folder is answered the bar goes quiet",
          walked.pillCount == "Idle", walked.pillCount)
    check("a single file is counted in the singular",
          TidyFlow(groups: [TidyGroup(name: "One", reason: "", files: [waiting("z.pdf", minutesAgo: 1)])],
                   isRenaming: true).waitingTitle == "1 file waiting")

    // MARK: - Moving between folders without answering
    //
    // Looking at what else is in the pile is not a decision. Everything here
    // guards the difference: a folder you paged past is still waiting, and
    // the walk is over when every folder has been answered — not when the
    // cursor happens to be at the end.

    print("\n[paging through the folders]")

    func threeFolders() -> TidyFlow {
        TidyFlow(groups: (1...3).map { index in
            TidyGroup(name: "Folder \(index)", reason: "",
                      files: [waiting("f\(index).pdf", minutesAgo: Double(index))])
        }, isRenaming: true)
    }

    var paging = threeFolders()
    check("it starts on the first folder", paging.step == 0)
    check("with nowhere behind it", !paging.canShowPrevious)
    check("and somewhere ahead", paging.canShowNext)

    paging.showNext()
    check("paging forward moves the cursor", paging.step == 1)
    check("and nothing is counted as answered",
          paging.pendingGroupCount == 3, "\(paging.pendingGroupCount)")
    check("so the pile has not shrunk", paging.pendingFiles.count == 3)

    paging.showPrevious()
    check("paging back returns to it", paging.step == 0)
    paging.showPrevious()
    check("and cannot go back past the first", paging.step == 0)

    paging.show(groupAt: 2)
    check("a folder can be jumped to outright", paging.step == 2)
    paging.showNext()
    check("the last folder has nothing ahead of it", paging.step == 2)
    paging.show(groupAt: 99)
    check("a folder that does not exist is ignored", paging.step == 2)

    // Answering from the middle: the ones behind are still owed an answer.
    var middle = threeFolders()
    middle.show(groupAt: 1)
    middle.skip()
    check("answering the middle folder moves to the one after it", middle.step == 2)
    check("and only that one is counted as answered",
          middle.pendingGroupCount == 2, "\(middle.pendingGroupCount)")
    middle.skip()
    check("answering the last one comes back for the first",
          middle.step == 0, "\(middle.step)")
    check("which is still unfinished", middle.stage != .idle)
    if case .finished = middle.stage {
        check("a folder still unanswered means the walk is not over", false)
    } else {
        check("a folder still unanswered means the walk is not over", true)
    }
    middle.skip()
    guard case .finished = middle.stage else {
        check("answering every folder ends the walk", false); return
    }
    check("answering every folder ends the walk", true)

    var jumped = threeFolders()
    jumped.skip()
    jumped.show(groupAt: 0)
    check("a folder already answered cannot be gone back to", jumped.step == 1)

    // MARK: - What counts as a swipe

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

    print("\n[how long it has been sitting there]")

    var fixed = DateComponents()
    fixed.year = 2026; fixed.month = 9; fixed.day = 15
    fixed.hour = 22; fixed.minute = 0
    // A fixed instant, so the yesterday check cannot change its mind when the
    // suite happens to run just after midnight.
    guard let fixedNow = Calendar.current.date(from: fixed) else {
        check("the fixed clock could be built", false); return
    }
    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = fixed
        parts.day = day; parts.hour = hour; parts.minute = minute
        return Calendar.current.date(from: parts)!
    }

    check("minutes while it is still minutes",
          TidyFile.age(of: at(15, 21, 56), now: fixedNow) == "4m",
          TidyFile.age(of: at(15, 21, 56), now: fixedNow))
    check("hours later the same day",
          TidyFile.age(of: at(15, 19, 0), now: fixedNow) == "3h",
          TidyFile.age(of: at(15, 19, 0), now: fixedNow))
    check("yesterday is yesterday",
          TidyFile.age(of: at(14, 19, 43), now: fixedNow) == "Yest.",
          TidyFile.age(of: at(14, 19, 43), now: fixedNow))
    // 46 hours, which the old arithmetic called yesterday because it counted
    // hours and divided by 24. Sunday night is not yesterday on a Tuesday.
    check("and the night before last is not",
          TidyFile.age(of: at(13, 23, 30), now: fixedNow) == "2d",
          TidyFile.age(of: at(13, 23, 30), now: fixedNow))

    func arrived(_ name: String, _ date: Date) -> TidyFile {
        TidyFile(moveID: UUID(), currentName: name, proposedName: nil,
                 kindSymbol: "doc", addedAt: date)
    }

    // A folder filled in one evening: every age is "Yest.", so five tiles say
    // the same thing and none of them says which file it is.
    let sameEvening = TidyFlow(groups: [TidyGroup(name: "Evening", reason: "", files: [
        arrived("a.pdf", at(14, 19, 43)),
        arrived("b.pdf", at(14, 21, 8)),
        arrived("c.pdf", at(14, 21, 54))
    ])], isRenaming: true)
    let evening = sameEvening.trayCaptions(now: fixedNow)
    check("identical ages fall back to clock times",
          Set(evening.values) == ["19:43", "21:08", "21:54"],
          "\(evening.values.sorted())")

    let spread = TidyFlow(groups: [TidyGroup(name: "Spread", reason: "", files: [
        arrived("d.pdf", at(15, 21, 56)),
        arrived("e.pdf", at(14, 19, 43))
    ])], isRenaming: true)
    check("ages that already differ are left as ages",
          Set(spread.trayCaptions(now: fixedNow).values) == ["4m", "Yest."],
          "\(spread.trayCaptions(now: fixedNow).values.sorted())")

    check("and the tray accounts for what is being left alone",
          TidyFlow(groups: [TidyGroup(name: "Evening", reason: "",
                                      files: [arrived("a.pdf", at(14, 19, 43))])],
                   isRenaming: true, leftAlone: 3)
            .waitingDetail(now: fixedNow).hasSuffix("3 left alone"),
          TidyFlow(groups: [TidyGroup(name: "Evening", reason: "",
                                      files: [arrived("a.pdf", at(14, 19, 43))])],
                   isRenaming: true, leftAlone: 3).waitingDetail(now: fixedNow))
}
