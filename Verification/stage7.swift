import Foundation
import HootKit
import HootPlatformMac

/// Sorting by type is the mode people pick when they do not want Hoot to
/// interpret anything, so what it needs to be is *predictable*. These checks
/// hold it to that: the same filename always lands in the same folder, files
/// it does not recognize are left alone rather than swept into a junk drawer,
/// and nothing it produces can point outside the watched folder.
func stage7(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ label: String, _ ok: Bool, _ detail: String = "") { rawCheck(label, ok, detail) }

    let root = sandbox.appending(path: "by-type")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // (filename, the folder it must land in — nil means "left where it is")
    let cases: [(String, String?)] = [
        ("Screenshot 2026-09-12 at 7.47.44 pm.png", "Screenshots"),
        ("Screen Shot 2019-03-01 at 11.02.10 AM.png", "Screenshots"),   // pre-Mojave
        ("CleanShot 2026-01-04 at 09.11.22@2x.png", "Screenshots"),
        ("SCR-20260912-abcd.png", "Screenshots"),                        // Shottr
        ("IMG_2948.png", "Images"),
        ("holiday.jpeg", "Images"),
        ("contract.pdf", "PDFs"),
        ("notes.docx", "Documents"),
        ("todo.md", "Documents"),
        ("budget.xlsx", "Spreadsheets"),
        ("novel.epub", "Books"),
        ("demo.mp4", "Videos"),
        ("Screen Recording 2026-09-12 at 7.48.17 pm.mov", "Videos"),
        ("interview.mp3", "Audio"),
        ("backup.zip", "Archives"),
        ("Installer.dmg", "Installers"),
        ("mystery.qqq", nil),
        ("no-extension", nil)
    ]

    for (name, _) in cases {
        try? Data("x".utf8).write(to: root.appending(path: name))
    }
    let files = cases.compactMap { FileAnalyzer.analyze(root.appending(path: $0.0)) }

    print("\n[by type: a filename decides, and always the same way]")
    check("every fixture was discovered", files.count == cases.count,
          "got \(files.count) of \(cases.count)")

    for (name, expected) in cases {
        guard let file = files.first(where: { $0.filename == name }) else { continue }
        let got = TypeSorter.folder(for: file)
        check("\(name) -> \(expected ?? "left alone")", got == expected,
              "got \(got ?? "nil")")
    }

    // A screenshot is an image with a screenshot's name. Neither half alone
    // is enough, or a text file about screenshots would be filed as one.
    print("\n[by type: screenshots are images, not names]")
    let notes = root.appending(path: "screenshot ideas.txt")
    try? Data("x".utf8).write(to: notes)
    if let file = FileAnalyzer.analyze(notes) {
        check("a .txt named like a screenshot is not a screenshot",
              !TypeSorter.isScreenshot(file), "isScreenshot said true")
        check("it goes to Documents", TypeSorter.folder(for: file) == "Documents",
              "got \(TypeSorter.folder(for: file) ?? "nil")")
    }

    // ---- the plan itself ----
    print("\n[by type: the plan]")
    let planner = OrganizationPlanner()
    let plan = planner.makeTypePlan(root: root, files: files)

    let placed = Set(plan.allMoves.map(\.file.filename))
    let skippedNames = Set(plan.skipped.map(\.file.filename))
    let expectSkipped = Set(cases.filter { $0.1 == nil }.map(\.0))

    check("unrecognized files are skipped, not filed",
          skippedNames == expectSkipped,
          "skipped \(skippedNames.sorted())")
    check("no folder is invented for them",
          !plan.groups.contains { ["Other", "Unsorted", "Misc"].contains($0.name) },
          "groups: \(plan.groups.map(\.name).sorted())")
    check("every recognized file is placed",
          placed.count == cases.count - expectSkipped.count,
          "placed \(placed.count)")

    check("every move is actionable",
          plan.allMoves.allSatisfy { !$0.classification.isLowConfidence },
          "lowest \(plan.allMoves.map(\.classification.confidence).min() ?? -1)")
    check("folders stay flat — no role subfolders",
          plan.allMoves.allSatisfy { $0.roleSubfolder == nil })
    check("filenames are never rewritten",
          plan.allMoves.allSatisfy { $0.destinationName == $0.file.filename })

    // The safety rule the meaning path is already held to applies here too:
    // a destination has to stay inside the folder the user pointed at.
    let rootPath = root.standardizedFileURL.path
    check("no destination escapes the watched folder",
          plan.allMoves.allSatisfy {
              $0.destinationURL(root: root).standardizedFileURL.path.hasPrefix(rootPath + "/")
          })

    // Predictability is the feature. Two runs over the same folder must not
    // differ, or "you can guess what it will do" stops being true.
    let again = planner.makeTypePlan(root: root, files: files)
    check("the same folder plans the same way twice",
          plan.groups.map(\.name) == again.groups.map(\.name)
              && plan.allMoves.count == again.allMoves.count)

    // ---- the user's own vocabulary still wins ----
    print("\n[by type: the user's names outrank Hoot's]")
    var prefs = FolderPreferences()
    prefs.remember(proposed: "Screenshots", preferred: "Grabs")
    let renamed = planner.makeTypePlan(root: root, files: files, preferences: prefs)
    check("a remembered rename is applied",
          renamed.groups.contains { $0.name == "Grabs" },
          "groups: \(renamed.groups.map(\.name).sorted())")
    check("the rename can still be traced back to what Hoot proposed",
          renamed.groups.first { $0.name == "Grabs" }?.proposedName == "Screenshots",
          "proposed \(renamed.groups.first { $0.name == "Grabs" }?.proposedName ?? "nil")")

    // ---- the setting persists ----
    print("\n[by type: the choice is remembered]")
    let suite = "hoot.verify.\(UUID().uuidString)"
    if let defaults = UserDefaults(suiteName: suite) {
        check("defaults to sorting by meaning", SortingMode.load(from: defaults) == .byMeaning)
        SortingMode.byType.save(to: defaults)
        check("a chosen mode survives a relaunch",
              SortingMode.load(from: defaults) == .byType)
        check("sorting by type reaches no model", !SortingMode.byType.usesModel)
        check("sorting by meaning does", SortingMode.byMeaning.usesModel)
        defaults.removePersistentDomain(forName: suite)
    } else {
        check("could open a scratch defaults suite", false, suite)
    }

    try? FileManager.default.removeItem(at: root)
}
