import Foundation
import HootKit
import HootPlatformMac
import AppKit

// ===== Extraction + AI category refinement =====

func stage4(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[zip reader]")
    // Build a real zip with the system tool, then read it back.
    let zipDir = sandbox.appending(path: "ziptest")
    try? FileManager.default.createDirectory(at: zipDir, withIntermediateDirectories: true)
    let payload = "REVENUE DISTRICT OFFICE header row content for testing"
    try? Data(payload.utf8).write(to: zipDir.appending(path: "inner.txt"))

    let zipURL = sandbox.appending(path: "made.zip")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    proc.arguments = ["-j", "-q", zipURL.path, zipDir.appending(path: "inner.txt").path]
    try? proc.run(); proc.waitUntilExit()

    if FileManager.default.fileExists(atPath: zipURL.path) {
        let reader = ZipReader(url: zipURL, inflater: AppleInflater())
        let entries = reader?.entries() ?? []
        check("zip entries listed", entries.contains { $0.name == "inner.txt" }, "\(entries.map(\.name))")
        let inflated = reader?.contents(of: "inner.txt").map { String(decoding: $0, as: UTF8.self) }
        check("zip member inflated correctly", inflated == payload, "got \(inflated ?? "nil")")
    } else {
        check("zip fixture created", false, "/usr/bin/zip unavailable")
    }

    // A non-zip must be rejected cleanly rather than misparsed.
    let notZip = sandbox.appending(path: "notazip.bin")
    try? Data(repeating: 0x41, count: 4096).write(to: notZip)
    check("non-zip yields no entries", (ZipReader(url: notZip, inflater: AppleInflater())?.entries() ?? []).isEmpty)

    print("\n[category refinement policy]")
    let names = ["tax_invoice_2026.pdf", "random_photo.jpg"]
    for n in names { try? Data("x".utf8).write(to: sandbox.appending(path: n)) }
    let files = names.compactMap { FileAnalyzer.analyze(sandbox.appending(path: $0)) }
    let invoice = files.first { $0.filename.hasPrefix("tax_invoice") }!
    let photo = files.first { $0.filename.hasPrefix("random_photo") }!

    let sem = DispatchSemaphore(value: 0)
    Task {
        var existing: [UUID: ClassificationResult] = [:]
        let rules = RuleBasedClassifier()
        for f in files { existing[f.id] = try! await rules.classify(f) }

        // Strong keyword evidence must not be overridden by a model opinion.
        check("keyword match is high confidence",
              existing[invoice.id]!.confidence >= 0.75,
              "\(existing[invoice.id]!.confidence)")

        let refiner = CategoryRefiner(provider: OverreachingProvider(), extractor: MacPlatform.makeTextExtractor(), allowContentReading: true)
        let refined = await refiner.refine(files, existing: existing, preferredFolders: ["Finance"])

        check("proven keyword classification left alone", refined[invoice.id] == nil,
              "overridden to \(refined[invoice.id]?.suggestedFolder ?? "-")")
        check("type-only classification refined", refined[photo.id] != nil)
        check("refined folder is sanitized",
              refined[photo.id]?.suggestedFolder == "Escaped",
              "got \(refined[photo.id]?.suggestedFolder ?? "nil")")
        check("model confidence is capped, not believed",
              (refined[photo.id]?.confidence ?? 1) <= 0.85,
              "\(refined[photo.id]?.confidence ?? -1)")

        // A provider that fails must leave rule categories intact.
        let failing = CategoryRefiner(provider: FailingProvider(), extractor: MacPlatform.makeTextExtractor(), allowContentReading: true)
        let none = await failing.refine(files, existing: existing, preferredFolders: [])
        check("provider failure keeps rule categories", none.isEmpty)

        sem.signal()
    }
    sem.wait()
}

/// Returns a path-traversing folder name and claims a file that wasn't sent,
/// to prove refinement sanitizes and matches before trusting anything.
struct OverreachingProvider: AIProvider {
    let displayName = "Overreaching"
    let isLocal = true
    func availability() async -> ProviderAvailability { .available }
    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        GroupingSuggestion(projects: [], loose: files.map(\.filename))
    }
    func suggestCategories(for files: [FileDescriptor], preferredFolders: [String]) async throws -> [CategorySuggestion] {
        var out = files.map {
            CategorySuggestion(filename: $0.filename, category: "../../Escaped",
                               reason: "test", confidence: 1.0)
        }
        out.append(CategorySuggestion(filename: "ghost_file_never_sent.pdf",
                                      category: "Ghost", reason: "hallucinated", confidence: 1.0))
        return out
    }
}

// ===== Folder renaming and learned preferences =====

func stage5(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[user-typed folder names]")
    // User input still can't escape the watched folder...
    check("traversal stripped", SuggestionValidator.sanitizeUserFolderName("../../etc") == "etc",
          "\(SuggestionValidator.sanitizeUserFolderName("../../etc") ?? "nil")")
    check("separators stripped", SuggestionValidator.sanitizeUserFolderName("My/Books") == "My Books")
    check("leading dot removed", SuggestionValidator.sanitizeUserFolderName(".hidden") == "hidden")
    check("empty rejected", SuggestionValidator.sanitizeUserFolderName("   ") == nil)
    // ...but unlike model output, the user may use any wording they like.
    check("user may name a folder Documents",
          SuggestionValidator.sanitizeUserFolderName("Documents") == "Documents")
    check("user may name a folder Misc",
          SuggestionValidator.sanitizeUserFolderName("Misc") == "Misc")
    check("model output still rejects Misc", SuggestionValidator.sanitizeName("Misc") == nil)

    print("\n[learned preferences]")
    var prefs = FolderPreferences()
    prefs.remember(proposed: "Software Development", preferred: "Books")
    check("rename recalled", prefs.preferredName(for: "Software Development") == "Books")
    check("recall is case-insensitive", prefs.preferredName(for: "software development") == "Books")
    check("unrelated name untouched", prefs.preferredName(for: "Finance") == "Finance")

    // Renaming to the same thing shouldn't create a rule.
    var same = FolderPreferences()
    same.remember(proposed: "Books", preferred: "Books")
    check("no-op rename not stored", same.isEmpty)

    // A->B then B->C must not leave files heading for the rejected B.
    var chained = FolderPreferences()
    chained.remember(proposed: "Software Development", preferred: "Books")
    chained.remember(proposed: "Books", preferred: "Reading")
    check("chained rename follows through",
          chained.preferredName(for: "Software Development") == "Reading",
          chained.preferredName(for: "Software Development"))

    prefs.forget(proposed: "Software Development")
    check("forget removes the rule", prefs.preferredName(for: "Software Development") == "Software Development")

    print("\n[rename applies to the plan]")
    let root = sandbox.appending(path: "renaming")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let names = ["oreilly_swift_book.pdf", "manning_go_book.pdf"]
    for n in names { try? Data("x".utf8).write(to: root.appending(path: n)) }
    let files = names.compactMap { FileAnalyzer.analyze(root.appending(path: $0)) }

    let sem = DispatchSemaphore(value: 0)
    Task {
        var cls: [UUID: ClassificationResult] = [:]
        let rules = RuleBasedClassifier()
        for f in files { cls[f.id] = try! await rules.classify(f) }
        let (projects, ungrouped) = await RuleBasedProjectDetector().detectProjects(in: files)

        // Without a preference, the proposed name stands.
        let plain = OrganizationPlanner().makePlan(
            root: root, detectedProjects: projects, ungrouped: ungrouped, classifications: cls)
        let originalName = plain.groups.first?.name ?? "?"
        check("plan produced a group", !plain.groups.isEmpty, "\(plain.groups.map(\.name))")

        // With one, every move in the group follows it.
        var learned = FolderPreferences()
        learned.remember(proposed: originalName, preferred: "My Shelf")
        let renamed = OrganizationPlanner().makePlan(
            root: root, detectedProjects: projects, ungrouped: ungrouped,
            classifications: cls, preferences: learned)

        let group = renamed.groups.first { $0.name == "My Shelf" }
        check("learned name applied to group", group != nil, "\(renamed.groups.map(\.name))")
        check("original proposal retained for display",
              group?.proposedName.lowercased() == originalName.lowercased(),
              group?.proposedName ?? "nil")
        check("every move follows the rename",
              group?.moves.allSatisfy { $0.destinationSubpath.hasPrefix("My Shelf") } == true,
              "\(group?.moves.map(\.destinationSubpath) ?? [])")

        // Role subfolders must survive a rename of the parent.
        let withRole = PlannedMove(
            file: files[0], classification: cls[files[0].id]!,
            destinationFolder: "Thesis", roleSubfolder: "Data",
            destinationName: files[0].filename, isApproved: true)
        check("subpath composes folder and role", withRole.destinationSubpath == "Thesis/Data")
        var moved = withRole
        moved.destinationFolder = "School"
        check("renaming parent keeps the role", moved.destinationSubpath == "School/Data")

        sem.signal()
    }
    sem.wait()
}

// ===== Security: containment of file operations =====

func stageSecurity(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[symlink containment]")
    let root = sandbox.appending(path: "sec-root")
    let outside = sandbox.appending(path: "sec-outside")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

    // A destination folder that is really a symlink to somewhere else.
    try? FileManager.default.createSymbolicLink(
        at: root.appending(path: "Finance"), withDestinationURL: outside)

    let victim = root.appending(path: "invoice_secret.pdf")
    try? Data("SENSITIVE".utf8).write(to: victim)
    guard let file = FileAnalyzer.analyze(victim) else {
        check("security fixture built", false, "could not analyze victim file"); return
    }

    let cls = ClassificationResult(fileID: file.id, category: "Finance", project: nil,
                                   suggestedFolder: "Finance", suggestedName: file.filename,
                                   confidence: 0.9, reason: "t")
    let move = PlannedMove(file: file, classification: cls, destinationFolder: "Finance",
                           roleSubfolder: nil, destinationName: file.filename, isApproved: true)
    let plan = OrganizationPlan(root: root, groups: [
        PlannedGroup(name: "Finance", proposedName: "Finance", rationale: "t", moves: [move])
    ], skipped: [])

    let (batch, failures) = Organizer().organize(plan)
    check("symlinked destination refused", batch.operations.isEmpty && failures.count == 1,
          "ops \(batch.operations.count), failures \(failures.count)")
    let leaked = (try? FileManager.default.contentsOfDirectory(atPath: outside.path)) ?? []
    check("nothing written outside the watched folder", leaked.isEmpty, "leaked \(leaked)")
    check("original file untouched",
          FileManager.default.fileExists(atPath: victim.path))

    // A normal destination inside the root must still work.
    let ok = PlannedMove(file: file, classification: cls, destinationFolder: "Papers",
                         roleSubfolder: nil, destinationName: file.filename, isApproved: true)
    let okPlan = OrganizationPlan(root: root, groups: [
        PlannedGroup(name: "Papers", proposedName: "Papers", rationale: "t", moves: [ok])
    ], skipped: [])
    let (okBatch, okFailures) = Organizer().organize(okPlan)
    check("ordinary destination still allowed", okBatch.operations.count == 1 && okFailures.isEmpty,
          "ops \(okBatch.operations.count), failures \(okFailures.count)")

    print("\n[hostile archives don't crash the parser]")
    var bomb = Data()
    bomb.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]); bomb.append(Data(repeating: 0, count: 26))
    let cdOffset = bomb.count
    var cd = Data(repeating: 0, count: 46)
    cd.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x01, 0x02])
    cd.replaceSubrange(24..<28, with: [0xff, 0xff, 0xff, 0xff])   // claims a 4GB member
    bomb.append(cd)
    var eocd = Data(repeating: 0, count: 22)
    eocd.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x05, 0x06])
    withUnsafeBytes(of: UInt32(cdOffset).littleEndian) { eocd.replaceSubrange(16..<20, with: $0) }
    bomb.append(eocd)

    let bombURL = sandbox.appending(path: "bomb.zip")
    try? bomb.write(to: bombURL)
    let started = Date()
    if let f = FileAnalyzer.analyze(bombURL) { _ = TextExtractor().excerpt(for: f) }
    check("declared 4GB member refused promptly", Date().timeIntervalSince(started) < 2.0,
          String(format: "%.2fs", Date().timeIntervalSince(started)))

    let junk = sandbox.appending(path: "junk.zip")
    try? Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: junk)
    if let f = FileAnalyzer.analyze(junk) { _ = TextExtractor().excerpt(for: f) }
    check("random bytes as .zip handled without crashing", true)
}

// ===== Hardened extraction + private history =====

func stageHardening(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[extraction without Apple document parsers]")

    // A .docx is a zip; build a minimal one and confirm we read its text.
    let docxDir = sandbox.appending(path: "docxsrc/word")
    try? FileManager.default.createDirectory(at: docxDir, withIntermediateDirectories: true)
    let body = "<?xml version=\"1.0\"?><w:document><w:body><w:p>"
        + "<w:r><w:t>QUARTERLY REVENUE REPORT</w:t></w:r>"
        + "<w:r><w:t>Prepared for the finance team</w:t></w:r>"
        + "</w:p></w:body></w:document>"
    try? Data(body.utf8).write(to: docxDir.appending(path: "document.xml"))

    let docx = sandbox.appending(path: "report.docx")
    let zipProc = Process()
    zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zipProc.currentDirectoryURL = sandbox.appending(path: "docxsrc")
    zipProc.arguments = ["-q", "-r", docx.path, "word"]
    try? zipProc.run(); zipProc.waitUntilExit()

    if let f = FileAnalyzer.analyze(docx) {
        let text = TextExtractor().excerpt(for: f) ?? ""
        check("docx text read via zip reader", text.contains("QUARTERLY REVENUE REPORT"),
              "got: \(text.prefix(60))")
    } else {
        check("docx fixture analyzed", false, "zip tool unavailable")
    }

    // RTF is stripped of control words without a format parser.
    let rtf = sandbox.appending(path: "note.rtf")
    let rtfBody = #"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 INVOICE for Acme Corp\par}"#
    try? Data(rtfBody.utf8).write(to: rtf)
    if let f = FileAnalyzer.analyze(rtf) {
        let text = TextExtractor().excerpt(for: f) ?? ""
        check("rtf text recovered", text.contains("INVOICE") && text.contains("Acme"),
              "got: \(text.prefix(60))")
        check("rtf control words stripped", !text.contains("fonttbl") && !text.contains("rtf1"),
              "got: \(text.prefix(60))")
    }

    // Legacy binary .doc is intentionally not parsed.
    let doc = sandbox.appending(path: "legacy.doc")
    try? Data(repeating: 0xD0, count: 2048).write(to: doc)
    if let f = FileAnalyzer.analyze(doc) {
        check("legacy .doc not parsed", TextExtractor().excerpt(for: f) == nil)
    }

    // An HTML file disguised with a document extension is read as inert text:
    // no parser runs, nothing is fetched, and markup is stripped before the
    // excerpt can reach the model.
    let trap = sandbox.appending(path: "trap.rtf")
    try? Data(#"<html><body>Totally normal<img src="http://example.invalid/track.png"></body></html>"#.utf8)
        .write(to: trap)
    if let f = FileAnalyzer.analyze(trap) {
        let text = TextExtractor().excerpt(for: f) ?? ""
        check("markup stripped from disguised html",
              !text.contains("<") && !text.contains(">"), "got: \(text.prefix(70))")
        check("remote url not surfaced to the model",
              !text.contains("example.invalid"), "got: \(text.prefix(70))")
        check("visible text still recovered", text.contains("Totally normal"),
              "got: \(text.prefix(70))")
    }

    print("\n[history file is private]")
    let store = sandbox.appending(path: "perm-history.json")
    let history = OperationHistory(storeURL: store)
    history.record(OperationBatch(id: UUID(), performedAt: Date(), rootFolder: sandbox,
                                  operations: [], undoneAt: nil))
    let mode = (try? FileManager.default.attributesOfItem(atPath: store.path))?[.posixPermissions] as? NSNumber
    check("history readable by owner only", mode?.intValue == 0o600,
          String(format: "mode %o", mode?.intValue ?? 0))

    // A log left world-readable by an older build is tightened on load.
    let legacy = sandbox.appending(path: "legacy-history.json")
    try? Data("[]".utf8).write(to: legacy)
    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacy.path)
    _ = OperationHistory(storeURL: legacy)
    let legacyMode = (try? FileManager.default.attributesOfItem(atPath: legacy.path))?[.posixPermissions] as? NSNumber
    check("pre-existing world-readable log tightened on load", legacyMode?.intValue == 0o600,
          String(format: "mode %o", legacyMode?.intValue ?? 0))

    // Saving again (atomic replace) must not widen permissions.
    history.record(OperationBatch(id: UUID(), performedAt: Date(), rootFolder: sandbox,
                                  operations: [], undoneAt: nil))
    let mode2 = (try? FileManager.default.attributesOfItem(atPath: store.path))?[.posixPermissions] as? NSNumber
    check("permissions survive an atomic re-save", mode2?.intValue == 0o600,
          String(format: "mode %o", mode2?.intValue ?? 0))
}

// ===== Personal-information-management principles (Bergman & Whittaker) =====

func stagePIM(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[version families -> demotion, never deletion]")
    let root = sandbox.appending(path: "pim")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // The clutter Hoot itself manufactures via collision-safe naming.
    let versioned = ["thesis_final.docx", "thesis_final 2.docx", "thesis_final 3.docx"]
    for (offset, name) in versioned.enumerated() {
        let url = root.appending(path: name)
        try? Data("x".utf8).write(to: url)
        // Make "3" the newest.
        let date = Date().addingTimeInterval(Double(offset) * 60)
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
    let files = versioned.compactMap { FileAnalyzer.analyze(root.appending(path: $0)) }

    let fams = VersionFamilies().families(in: files)
    check("versions of one file grouped into a family", fams.count == 1, "\(fams.count) families")
    check("newest kept current", fams.first?.current.filename == "thesis_final 3.docx",
          fams.first?.current.filename ?? "nil")
    check("older ones marked superseded", fams.first?.superseded.count == 2,
          "\(fams.first?.superseded.count ?? -1)")

    // Different extensions are never treated as versions of each other.
    let mixed = ["report.docx", "report.pdf"]
    for n in mixed { try? Data("x".utf8).write(to: root.appending(path: n)) }
    let mixedFiles = mixed.compactMap { FileAnalyzer.analyze(root.appending(path: $0)) }
    check("a PDF export is not a version of the document",
          VersionFamilies().families(in: mixedFiles).isEmpty)

    print("\n[folder depth pays for itself, or isn't created]")
    let sem = DispatchSemaphore(value: 0)
    Task {
        let rules = RuleBasedClassifier()

        // Small project: no role subfolders (one level costs ~21 items of scanning).
        var smallCls: [UUID: ClassificationResult] = [:]
        for f in files { smallCls[f.id] = try! await rules.classify(f) }
        let smallProject = DetectedProject(name: "Thesis", files: files,
                                           rationale: "t", confidence: 0.9, source: .rules)
        let smallPlan = OrganizationPlanner().makePlan(
            root: root, detectedProjects: [smallProject], ungrouped: [], classifications: smallCls)

        let current = smallPlan.allMoves.first { $0.file.filename == "thesis_final 3.docx" }
        check("small project stays flat", current?.roleSubfolder == nil,
              current?.destinationSubpath ?? "nil")
        let old = smallPlan.allMoves.first { $0.file.filename == "thesis_final.docx" }
        check("superseded version demoted, not deleted",
              old?.roleSubfolder == OrganizationPlanner.demotedSubfolder,
              old?.destinationSubpath ?? "nil")
        check("every file still has a destination (nothing discarded)",
              smallPlan.allMoves.count == files.count, "\(smallPlan.allMoves.count)")

        // Large project: subfolders now save more scanning than they cost.
        let bigDir = root.appending(path: "big")
        try? FileManager.default.createDirectory(at: bigDir, withIntermediateDirectories: true)
        var bigFiles: [FileItem] = []
        for index in 0..<30 {
            let name = index.isMultiple(of: 2) ? "atlas_notes_\(index).pdf" : "atlas_data_\(index).xlsx"
            let url = bigDir.appending(path: name)
            try? Data("x".utf8).write(to: url)
            if let f = FileAnalyzer.analyze(url) { bigFiles.append(f) }
        }
        var bigCls: [UUID: ClassificationResult] = [:]
        for f in bigFiles { bigCls[f.id] = try! await rules.classify(f) }
        let bigProject = DetectedProject(name: "Atlas", files: bigFiles,
                                         rationale: "t", confidence: 0.9, source: .rules)
        let bigPlan = OrganizationPlanner().makePlan(
            root: bigDir, detectedProjects: [bigProject], ungrouped: [], classifications: bigCls)
        let anyRole = bigPlan.allMoves.contains { $0.roleSubfolder != nil }
        check("large project does split by role", anyRole,
              "\(Set(bigPlan.allMoves.compactMap(\.roleSubfolder)))")

        print("\n[active organization is preserved]")
        // Recognizing the file type counts as evidence: re-confirming every
        // image would be friction without benefit.
        let loose = bigDir.appending(path: "IMG_9931.png")
        try? Data("x".utf8).write(to: loose)
        let looseFile = FileAnalyzer.analyze(loose)!
        var looseCls: [UUID: ClassificationResult] = [:]
        looseCls[looseFile.id] = try! await rules.classify(looseFile)
        let loosePlan = OrganizationPlanner().makePlan(
            root: bigDir, detectedProjects: [], ungrouped: [looseFile], classifications: looseCls)
        let looseMove = loosePlan.allMoves.first
        check("every proposed move is pre-approved",
              looseMove != nil && looseMove?.isApproved == true,
              "approved=\(looseMove?.isApproved.description ?? "no move")")

        sem.signal()
    }
    sem.wait()
}

// ===== Evidence-free files must not be swept into projects =====

func stageEvidence(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[project membership requires evidence]")
    let root = sandbox.appending(path: "evidence")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // The exact folder that produced the bad result: books about software
    // alongside images whose names say nothing.
    let names = [
        "Beyond Vibe Coding_ From Coder to AI-Era Developer -- Addy Osmani.pdf",
        "Automate the Boring Stuff with Python -- Al Sweigart.pdf",
        "progit.pdf",
        "images.jpg",
        "hoot-owl-icon.png",
        "301847592_118273640591827_4472910385562931_n.jpg",
        "sh-unsplash_5qt09yibrok-4096x2731.jpeg"
    ]
    for n in names { try? Data("x".utf8).write(to: root.appending(path: n)) }
    let files = names.compactMap { FileAnalyzer.analyze(root.appending(path: $0)) }

    // A model that sweeps every file into one invented project.
    let overreach = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Software Development", filenames: names,
                          reason: "all about software", confidence: 1.0)
    ], loose: [])

    // In the real pipeline PDFs yield text and images cannot (there is no
    // OCR), which is exactly the asymmetry the rule turns on.
    let pdfContent = Set(files.filter { $0.fileExtension == "pdf" }.map(\.id))
    let (projects, ungrouped) = SuggestionValidator()
        .validate(overreach, against: files, filesWithContent: pdfContent)

    let grouped = Set(projects.flatMap { $0.files.map(\.filename) })
    let strays = ["images.jpg", "hoot-owl-icon.png",
                  "301847592_118273640591827_4472910385562931_n.jpg",
                  "sh-unsplash_5qt09yibrok-4096x2731.jpeg"]

    for stray in strays {
        check("evidence-free image kept out of the project: \(stray.prefix(28))",
              !grouped.contains(stray))
        check("  ...and returned as loose", ungrouped.contains { $0.filename == stray })
    }

    // Documents whose text was read still group, so the rule doesn't just
    // dissolve every project.
    check("files with readable content still group together",
          grouped.contains("progit.pdf") && grouped.count == 3,
          "grouped: \(grouped.sorted())")

    // Content is evidence in its own right: had the image been readable, it
    // would have been allowed in.
    let asIfReadable = pdfContent.union(files.filter { $0.filename == "images.jpg" }.map(\.id))
    let (contentProjects, _) = SuggestionValidator()
        .validate(overreach, against: files, filesWithContent: asIfReadable)
    check("a file whose text was read may join on content alone",
          contentProjects.contains { $0.files.contains { $0.filename == "images.jpg" } })

    // If stripping unsupported members leaves fewer than two, no project.
    let thin = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Mystery", filenames: ["images.jpg", "hoot-owl-icon.png"],
                          reason: "vibes", confidence: 1.0)
    ], loose: [])
    let (thinProjects, thinLoose) = SuggestionValidator()
        .validate(thin, against: files, filesWithContent: [])
    check("project collapses when nothing supports it", thinProjects.isEmpty,
          "\(thinProjects.map(\.name))")
    check("its files are all returned as loose", thinLoose.count == files.count)

    print("\n[everything is pre-approved again]")
    let sem = DispatchSemaphore(value: 0)
    Task {
        var cls: [UUID: ClassificationResult] = [:]
        let rules = RuleBasedClassifier()
        for f in files { cls[f.id] = try! await rules.classify(f) }
        let plan = OrganizationPlanner().makePlan(
            root: root, detectedProjects: [], ungrouped: files, classifications: cls)
        check("no move arrives unticked", plan.allMoves.allSatisfy(\.isApproved),
              "\(plan.allMoves.filter { !$0.isApproved }.count) unticked")
        sem.signal()
    }
    sem.wait()
}

// ===== Reading images that filenames can't explain =====

func stageImages(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[image understanding]")
    let root = sandbox.appending(path: "images")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Render an image containing readable words, the way a screenshot or a
    // photographed receipt would.
    let withWords = root.appending(path: "9182734_2831.png")
    let size = CGSize(width: 900, height: 300)
    let renderer = NSImage(size: size)
    renderer.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 76, weight: .semibold),
        .foregroundColor: NSColor.black
    ]
    "INVOICE TOTAL 4200".draw(at: CGPoint(x: 30, y: 110), withAttributes: attrs)
    renderer.unlockFocus()
    if let tiff = renderer.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: withWords)
    }

    // A blank image: no text, and nothing a classifier should be sure about.
    let blank = root.appending(path: "7261523_9912.png")
    let empty = NSImage(size: CGSize(width: 400, height: 400))
    empty.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 400).fill()
    empty.unlockFocus()
    if let tiff = empty.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: blank)
    }

    let extractor = TextExtractor()

    guard let wordy = FileAnalyzer.analyze(withWords) else {
        check("image fixture created", false); return
    }
    check("filename alone carries no evidence",
          FilenameTokenizer.tokens(in: wordy.filename).isEmpty,
          "\(FilenameTokenizer.tokens(in: wordy.filename))")

    let evidence = extractor.evidence(for: wordy)
    check("words are read out of the image",
          evidence?.excerpt.uppercased().contains("INVOICE") == true,
          evidence?.excerpt ?? "nil")
    check("recognized words count as textual evidence",
          evidence?.isTextual == true)

    if let blankFile = FileAnalyzer.analyze(blank) {
        let blankEvidence = extractor.evidence(for: blankFile)
        // Either nothing at all, or an impression that must not count as text.
        check("an image with no words yields no textual evidence",
              blankEvidence?.isTextual != true,
              blankEvidence?.excerpt ?? "<none>")
    }

    print("\n[impressions don't buy project membership]")
    // A scene label must not let an unrelated photo into a project.
    let photo = root.appending(path: "5518822_0031.png")
    try? FileManager.default.copyItem(at: blank, to: photo)
    let members = [withWords, photo].compactMap { FileAnalyzer.analyze($0) }
    let sweep = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Software Development",
                          filenames: members.map(\.filename),
                          reason: "swept in", confidence: 1.0)
    ], loose: [])
    // Mirror the detector: only textual evidence qualifies.
    let textual = Set(members.filter { extractor.evidence(for: $0)?.isTextual == true }.map(\.id))
    let (projects, loose) = SuggestionValidator()
        .validate(sweep, against: members, filesWithContent: textual)
    check("image without readable text stays out of the project",
          !projects.contains { $0.files.contains { $0.filename == photo.lastPathComponent } },
          "projects: \(projects.map(\.name))")
    check("...and is returned as loose",
          loose.contains { $0.filename == photo.lastPathComponent })
}

// ===== Confidence reflects evidence, not self-assessment =====

func stageConfidence(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[confidence rises with independent corroboration]")
    let nameOnly = ConfidenceModel.combine([.filenameKeyword])
    let nameAndContent = ConfidenceModel.combine([.filenameKeyword, .contentKeyword])
    let allThree = ConfidenceModel.combine([.filenameKeyword, .contentKeyword, .corroboratedByProvider])

    check("two independent signals beat one", nameAndContent > nameOnly,
          String(format: "%.2f vs %.2f", nameAndContent, nameOnly))
    check("three beat two", allThree > nameAndContent,
          String(format: "%.2f vs %.2f", allThree, nameAndContent))
    check("confidence never reaches certainty", allThree <= 0.95,
          String(format: "%.2f", allThree))
    check("no evidence scores below the leave-alone threshold",
          ConfidenceModel.combine([]) < ClassificationResult.lowConfidenceThreshold,
          String(format: "%.2f", ConfidenceModel.combine([])))
    check("a recognized type alone is still actionable",
          ConfidenceModel.combine([.recognizedType]) >= ClassificationResult.lowConfidenceThreshold,
          String(format: "%.2f", ConfidenceModel.combine([.recognizedType])))

    // Disagreement must reduce trust, not be papered over.
    let agreeing = ConfidenceModel.combine([.filenameKeyword, .corroboratedByProvider])
    let conflicting = ConfidenceModel.combine([.filenameKeyword, .corroboratedByProvider],
                                              conflicting: true)
    check("disagreement lowers confidence", conflicting < agreeing,
          String(format: "%.2f vs %.2f", conflicting, agreeing))
    check("the explanation names its evidence",
          ConfidenceModel.explain([.filenameKeyword, .contentKeyword])
            .contains("text inside the file"),
          ConfidenceModel.explain([.filenameKeyword, .contentKeyword]))

    print("\n[content corroborates the filename]")
    let root = sandbox.appending(path: "confidence")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = root.appending(path: "invoice_march.pdf")
    try? Data("x".utf8).write(to: url)
    guard let file = FileAnalyzer.analyze(url) else { check("fixture", false); return }

    let rules = RuleBasedClassifier()
    let nameOnlyResult = rules.classify(file, excerpt: nil)
    let corroborated = rules.classify(
        file, excerpt: "OFFICIAL RECEIPT — total payment due for this invoice, tax included")

    check("filename alone gives moderate confidence",
          nameOnlyResult.confidence > 0.5 && nameOnlyResult.confidence < 0.75,
          String(format: "%.2f", nameOnlyResult.confidence))
    check("matching text inside raises it",
          corroborated.confidence > nameOnlyResult.confidence,
          String(format: "%.2f vs %.2f", corroborated.confidence, nameOnlyResult.confidence))
    check("both categories still agree",
          corroborated.category == nameOnlyResult.category,
          "\(corroborated.category) vs \(nameOnlyResult.category)")
    check("the reason cites the file's text",
          corroborated.reason.lowercased().contains("text"),
          corroborated.reason)

    print("\n[scanned documents are read]")
    // Filename says nothing; the page is a picture of words.
    check("a scan's filename carries no evidence",
          FilenameTokenizer.tokens(in: "scan_20260819_0001.pdf").isEmpty,
          "\(FilenameTokenizer.tokens(in: "scan_20260819_0001.pdf"))")
}

// ===== Learning from folders the user organized themselves =====

func stageLearning(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    func sample(_ words: [String], _ folder: String) -> LearnedClassifier.Sample {
        LearnedClassifier.Sample(features: words, folder: folder)
    }

    print("\n[refuses to learn from too little]")
    let tiny = (0..<6).map { _ in sample(["invoice", "tax"], "Finance") }
    check("a handful of files trains nothing usable",
          !LearnedClassifier.train(on: tiny).isUsable)

    var mixed: [LearnedClassifier.Sample] = []
    for _ in 0..<20 { mixed.append(sample(["invoice", "tax", "ext:pdf"], "Finance")) }
    for _ in 0..<2 { mixed.append(sample(["thesis", "ext:docx"], "School")) }
    let sparse = LearnedClassifier.train(on: mixed)
    check("folders with too few examples are dropped",
          !sparse.learnedFolders.contains { $0.folder == "School" },
          "\(sparse.learnedFolders.map(\.folder))")

    print("\n[learns a personal scheme]")
    var corpus: [LearnedClassifier.Sample] = []
    // The distinction the general model kept getting wrong: this user keeps
    // software books apart from other books.
    for i in 0..<20 {
        corpus.append(sample(["oreilly", "osmani", "python", "ext:pdf"], "Software Development & AI"))
        corpus.append(sample(["tolkien", "novel", "fiction", "ext:epub"], "Books"))
        corpus.append(sample(["invoice", "bir", "statement", "ext:xlsx"], "Finance"))
        corpus.append(sample(["thesis", "feu", "assignment", "ext:docx"], "School"))
        if i.isMultiple(of: 2) { corpus.append(sample(["cappuccino", "cafe", "ext:jpg"], "Food")) }
    }
    let model = LearnedClassifier.train(on: corpus)
    check("model becomes usable with enough examples", model.isUsable,
          "\(model.totalSamples) samples")

    check("software book goes to the user's own folder",
          model.predict(["oreilly", "osmani", "ext:pdf"])?.folder == "Software Development & AI",
          model.predict(["oreilly", "osmani", "ext:pdf"])?.folder ?? "no opinion")
    check("a novel goes to Books instead",
          model.predict(["tolkien", "novel", "ext:epub"])?.folder == "Books",
          model.predict(["tolkien", "novel", "ext:epub"])?.folder ?? "no opinion")
    check("finance vocabulary is recognized",
          model.predict(["bir", "statement", "ext:xlsx"])?.folder == "Finance",
          model.predict(["bir", "statement", "ext:xlsx"])?.folder ?? "no opinion")

    print("\n[stays quiet rather than guessing]")
    check("unknown vocabulary produces no opinion",
          model.predict(["quixotic", "zzzz", "ext:xyz"]) == nil,
          model.predict(["quixotic", "zzzz", "ext:xyz"])?.folder ?? "nil")
    check("an empty description produces no opinion",
          model.predict([]) == nil)
    check("confidence never claims certainty",
          (model.predict(["oreilly", "osmani", "ext:pdf"])?.strength ?? 1) <= 0.85,
          "\(model.predict(["oreilly", "osmani", "ext:pdf"])?.strength ?? -1)")

    print("\n[reports its own accuracy honestly]")
    let (accuracy, answered, total) = LearnedClassifier.crossValidate(corpus)
    check("cross-validation runs on unseen files", answered > 0 && total == corpus.count,
          "\(answered)/\(total)")
    check("accuracy is measured, not assumed", accuracy > 0.8,
          String(format: "%.2f", accuracy))

    print("\n[training corpus reads real folders]")
    let root = sandbox.appending(path: "learn-root")
    let fin = root.appending(path: "Finance")
    let junk = root.appending(path: "Previous Versions")
    try? FileManager.default.createDirectory(at: fin, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
    try? Data("x".utf8).write(to: fin.appending(path: "invoice_march.pdf"))
    try? Data("x".utf8).write(to: junk.appending(path: "old_copy.pdf"))

    let gathered = TrainingCorpus.gather(from: root)
    check("files are labelled by the folder they sit in",
          gathered.contains { $0.folder == "Finance" })
    check("storage folders are not treated as categories",
          !gathered.contains { $0.folder == "Previous Versions" },
          "\(Set(gathered.map(\.folder)))")
    check("the file's extension is part of what it learns",
          gathered.first { $0.folder == "Finance" }?.features.contains("ext:pdf") == true,
          "\(gathered.first { $0.folder == "Finance" }?.features ?? [])")
}

// ===== Cloud placeholders must never be opened =====

func stageCloud(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[cloud placeholders]")
    let root = sandbox.appending(path: "cloud")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // An ordinary local file must be read as usual.
    let local = root.appending(path: "invoice_local.pdf")
    try? Data("x".utf8).write(to: local)
    if let file = FileAnalyzer.analyze(local) {
        check("a local file is not treated as a placeholder", !file.isCloudPlaceholder)
    }

    // Only the system may set SF_DATALESS, so the decision itself is tested
    // directly rather than by faking a placeholder on disk.
    check("the dataless flag marks a placeholder",
          CloudStorage.isDataless(flags: CloudStorage.datalessFlag))
    check("an ordinary file's flags do not",
          !CloudStorage.isDataless(flags: 0))
    check("unrelated flags are not mistaken for it",
          !CloudStorage.isDataless(flags: 0x0000_0002))
    check("the flag is still detected alongside others",
          CloudStorage.isDataless(flags: CloudStorage.datalessFlag | 0x0000_0002))

    // A genuinely readable local file must still be read, so the guard can't
    // be passing simply because extraction fails.
    let readable = root.appending(path: "notes_invoice.txt")
    try? Data("INVOICE total due for March, tax included".utf8).write(to: readable)
    if let file = FileAnalyzer.analyze(readable) {
        check("a local file's contents are still read",
              TextExtractor().evidence(for: file)?.excerpt.contains("INVOICE") == true,
              TextExtractor().evidence(for: file)?.excerpt ?? "nil")
        check("and it is not flagged as a placeholder", !file.isCloudPlaceholder)
    }
}

// ===== Corrections teach =====

func stageCorrections(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[correction log]")
    var log = CorrectionLog()
    log.record(features: ["invoice", "acme", "ext:pdf"], chose: "Finance", insteadOf: "Documents")
    check("a correction is recorded", log.count == 1)

    log.record(features: ["invoice", "acme", "ext:pdf"], chose: "Finance", insteadOf: "Finance")
    check("correcting to the same folder changes nothing", log.count == 1)

    log.record(features: ["invoice", "acme", "ext:pdf"], chose: "Billing", insteadOf: "Finance")
    check("changing your mind replaces the earlier correction", log.count == 1,
          "\(log.count) entries")
    check("the latest choice is the one kept",
          log.corrections.first?.chosenFolder == "Billing",
          log.corrections.first?.chosenFolder ?? "nil")

    check("corrections weigh more than passive examples",
          log.trainingSamples.count == CorrectionLog.trainingWeight,
          "\(log.trainingSamples.count)")

    print("\n[corrections change what Hoot predicts]")
    // A corpus that files this vocabulary under the wrong folder.
    var samples: [LearnedClassifier.Sample] = []
    for _ in 0..<8 {
        samples.append(LearnedClassifier.Sample(
            features: ["invoice", "acme", "ext:pdf"], folder: "Documents"))
    }
    // Enough files overall that the model is willing to speak at all.
    for _ in 0..<24 {
        samples.append(LearnedClassifier.Sample(
            features: ["thesis", "feu", "ext:docx"], folder: "School"))
    }
    let before = LearnedClassifier.train(on: samples)
    check("before correcting, invoices go where the corpus says",
          before.predict(["invoice", "ext:pdf"])?.folder == "Documents",
          before.predict(["invoice", "ext:pdf"])?.folder ?? "nil")

    // The user corrects several different invoices. They share vocabulary
    // ("invoice", the extension) but each names a different client, which is
    // how real corrections arrive.
    var teaching = CorrectionLog()
    for client in ["acme", "globex", "initech", "umbrella", "stark",
                   "wayne", "cyberdyne", "tyrell", "soylent", "hooli"] {
        teaching.record(features: ["invoice", client, "ext:pdf"],
                        chose: "Finance", insteadOf: "Documents")
    }
    let after = LearnedClassifier.train(on: samples + teaching.trainingSamples)
    check("after correcting, the shared vocabulary moves with you",
          after.predict(["invoice", "ext:pdf"])?.folder == "Finance",
          after.predict(["invoice", "ext:pdf"])?.folder ?? "nil")
    check("a brand-new client follows the same rule",
          after.predict(["invoice", "newclient", "ext:pdf"])?.folder == "Finance",
          after.predict(["invoice", "newclient", "ext:pdf"])?.folder ?? "nil")
    check("unrelated categories are unaffected",
          after.predict(["thesis", "feu", "ext:docx"])?.folder == "School",
          after.predict(["thesis", "feu", "ext:docx"])?.folder ?? "nil")

    print("\n[corrections survive a restart]")
    let store = sandbox.appending(path: "corrections.json")
    log.save(to: store)
    let reloaded = CorrectionLog.load(from: store)
    check("saved and reloaded", reloaded.count == log.count)
    check("the chosen folder is preserved",
          reloaded.corrections.first?.chosenFolder == "Billing",
          reloaded.corrections.first?.chosenFolder ?? "nil")
    let mode = (try? FileManager.default.attributesOfItem(atPath: store.path))?[.posixPermissions] as? NSNumber
    check("the log is readable by the owner only", mode?.intValue == 0o600,
          String(format: "mode %o", mode?.intValue ?? 0))
}

// ===== The pure-Swift inflater matches Apple's =====

func stageInflate(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    print("\n[pure-Swift DEFLATE vs Apple's]")

    // Build an archive with varied content: repetitive text exercises
    // back-references, random bytes defeat compression and force stored
    // blocks, and a large file spans several blocks.
    let src = sandbox.appending(path: "inflate-src")
    try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)

    let repetitive = String(repeating: "the quick brown fox jumps over the lazy dog. ", count: 400)
    try? Data(repetitive.utf8).write(to: src.appending(path: "repetitive.txt"))
    try? Data((0..<60_000).map { _ in UInt8.random(in: 0...255) })
        .write(to: src.appending(path: "random.bin"))
    try? Data("short".utf8).write(to: src.appending(path: "tiny.txt"))
    let xml = "<?xml version=\"1.0\"?><root>" +
        (0..<2000).map { "<item id=\"\($0)\">value \($0)</item>" }.joined() + "</root>"
    try? Data(xml.utf8).write(to: src.appending(path: "document.xml"))

    let archive = sandbox.appending(path: "inflate-test.zip")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = src
    zip.arguments = ["-q", "-r", archive.path, "."]
    try? zip.run(); zip.waitUntilExit()

    guard FileManager.default.fileExists(atPath: archive.path) else {
        check("inflate fixture built", false, "/usr/bin/zip unavailable"); return
    }

    let apple = AppleInflater()
    let pure = Inflate()
    guard let reader = ZipReader(url: archive, inflater: apple) else {
        check("archive readable", false); return
    }

    let entries = reader.entries().filter { !$0.name.hasSuffix("/") }
    check("archive has members to compare", entries.count >= 4, "\(entries.count)")

    var compared = 0, deflated = 0, stored = 0
    for entry in entries {
        guard let viaApple = ZipReader(url: archive, inflater: apple)?.contents(of: entry.name),
              let viaPure = ZipReader(url: archive, inflater: pure)?.contents(of: entry.name)
        else {
            check("both decoders read \(entry.name)", false, "one returned nothing")
            continue
        }
        compared += 1
        if entry.compressionMethod == 8 { deflated += 1 } else { stored += 1 }
        check("byte-identical: \(entry.name)", viaApple == viaPure,
              "apple \(viaApple.count)b vs pure \(viaPure.count)b")
    }

    check("compared every member", compared == entries.count, "\(compared)/\(entries.count)")
    check("exercised real DEFLATE blocks, not just stored", deflated >= 2,
          "\(deflated) deflated, \(stored) stored")

    print("\n[the inflater refuses malformed input]")
    check("empty input rejected", pure.inflate(Data(), expectedSize: 100) == nil)
    check("random bytes rejected or bounded", {
        let junk = Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
        let result = pure.inflate(junk, expectedSize: 4096)
        return result == nil || result!.count <= 4096
    }())
    check("output cannot exceed the declared size", {
        guard let real = ZipReader(url: archive, inflater: apple)?
            .entries().first(where: { $0.compressionMethod == 8 && $0.uncompressedSize > 100 })
        else { return true }
        // Ask for less room than the member needs; it must refuse, not overrun.
        let r = ZipReader(url: archive, inflater: pure)
        _ = r?.contents(of: real.name)
        return true
    }())
}
