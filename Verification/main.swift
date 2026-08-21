import Foundation
import HootKit
import HootPlatformMac
import AppKit

// Exercises the real Hoot services against a throwaway sandbox folder:
// discovery -> classification -> grouping -> plan -> move -> undo.

let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "hoot-verify-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

let filenames = [
    "thesis_final.docx",
    "thesis_chapter2.docx",
    "survey_results.xlsx",
    "thesis_research_article.pdf",
    "invoice_client.pdf",
    "invoice_march.pdf",
    "IMG_2948.png",
    ".DS_Store",                 // must be ignored
    "big_download.crdownload"    // in-progress marker
]
for name in filenames {
    try! Data("x".utf8).write(to: sandbox.appending(path: name))
}

var failures = 0
func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("  PASS  \(label)") }
    else { failures += 1; print("  FAIL  \(label) \(detail)") }
}

// ---- discovery ----
let discovered = (try! FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil))
    .filter { !FileAnalyzer.isIgnored($0) }
    .compactMap { FileAnalyzer.analyze($0) }

print("\n[discovery]")
check("hidden files ignored", !discovered.contains { $0.filename == ".DS_Store" })
check("partial download ignored", !discovered.contains { $0.fileExtension == "crdownload" })
check("found 7 real files", discovered.count == 7, "got \(discovered.count)")

// ---- classification ----
print("\n[classification]")
var classifications: [UUID: ClassificationResult] = [:]
let sem = DispatchSemaphore(value: 0)
Task {
    let classifier = RuleBasedClassifier()
    for file in discovered {
        classifications[file.id] = try! await classifier.classify(file)
    }
    sem.signal()
}
sem.wait()

let invoice = discovered.first { $0.filename == "invoice_client.pdf" }!
check("invoice -> Finance", classifications[invoice.id]?.category == "Finance",
      "got \(classifications[invoice.id]?.category ?? "nil")")
let img = discovered.first { $0.filename == "IMG_2948.png" }!
// A camera-roll name carries no project hint, but we still know for certain
// it is an image — that must be confident enough to file, not discarded.
check("recognized image is confident despite meaningless name",
      !classifications[img.id]!.isLowConfidence,
      "conf \(classifications[img.id]!.confidence)")
check("recognized image routed to Images",
      classifications[img.id]!.suggestedFolder == "Images",
      classifications[img.id]!.suggestedFolder)

// ---- grouping ----
print("\n[grouping]")
let (groups, ungrouped) = ProjectGrouper().group(discovered)
let thesis = groups.first { $0.name == "Thesis" }
check("detected a Thesis project", thesis != nil, "groups: \(groups.map(\.name))")
check("thesis groups 3 files", thesis?.files.count == 3, "got \(thesis?.files.count ?? -1)")
let invoiceGroup = groups.first { $0.name == "Invoice" }
check("detected an Invoice project", invoiceGroup != nil)
check("lone image left ungrouped", ungrouped.contains { $0.filename == "IMG_2948.png" })

// ---- plan ----
print("\n[plan]")
let detectSem = DispatchSemaphore(value: 0)
var detected: (projects: [DetectedProject], ungrouped: [FileItem]) = ([], [])
Task {
    detected = await RuleBasedProjectDetector().detectProjects(in: discovered)
    detectSem.signal()
}
detectSem.wait()
let plan = OrganizationPlanner().makePlan(
    root: sandbox,
    detectedProjects: detected.projects,
    ungrouped: detected.ungrouped,
    classifications: classifications
)
check("plan is non-empty", !plan.isEmpty)
check("recognized image is planned, not abandoned",
      plan.allMoves.contains { $0.file.filename == "IMG_2948.png" }
      && !plan.skipped.contains { $0.file.filename == "IMG_2948.png" })
// Small projects stay flat: an extra folder level costs about as much time
// as scanning ~21 extra items, so it isn't worth it for a handful of files.
if let m = plan.allMoves.first(where: { $0.file.filename == "thesis_research_article.pdf" }) {
    check("small project stays flat rather than splitting by role",
          m.destinationSubpath == "Thesis", "got \(m.destinationSubpath)")
}
// KNOWN LIMIT (Stage 4): "survey_results.xlsx" belongs to the thesis
// semantically but shares no filename token with it, so token-based grouping
// correctly declines to guess and files it by category instead.
if let m = plan.allMoves.first(where: { $0.file.filename == "survey_results.xlsx" }) {
    check("unlinked spreadsheet falls back to its category", m.destinationSubpath == "Data",
          "got \(m.destinationSubpath)")
}
print("  plan:")
for g in plan.groups { for m in g.moves { print("    \(m.file.filename) -> \(m.destinationSubpath)/") } }

// ---- collision safety: pre-create a colliding destination ----
// Plant the decoy where the file will actually land, so the collision path
// is genuinely exercised.
let thesisDocs = sandbox.appending(path: "Thesis")
try! FileManager.default.createDirectory(at: thesisDocs, withIntermediateDirectories: true)
let decoy = thesisDocs.appending(path: "thesis_final.docx")
try! Data("PRE-EXISTING".utf8).write(to: decoy)

// ---- organize ----
print("\n[organize]")
let organizer = Organizer()
let (batch, moveFailures) = organizer.organize(plan)
check("no move failures", moveFailures.isEmpty, "\(moveFailures.map { $0.0.file.filename })")
check("operations recorded", batch.operations.count == plan.approvedMoves.count,
      "\(batch.operations.count) vs \(plan.approvedMoves.count)")
check("pre-existing file NOT overwritten",
      String(data: try! Data(contentsOf: decoy), encoding: .utf8) == "PRE-EXISTING")
let renamed = batch.operations.first { $0.source.lastPathComponent == "thesis_final.docx" }!
check("collision got a safe alternative name", renamed.destination.lastPathComponent != "thesis_final.docx",
      "got \(renamed.destination.lastPathComponent)")
print("    collided file landed as: \(renamed.destination.lastPathComponent)")
check("nothing was left behind unclassified", plan.skipped.isEmpty,
      "\(plan.skipped.map(\.file.filename))")
for op in batch.operations {
    check("moved: \(op.filename)", FileManager.default.fileExists(atPath: op.destination.path))
}

// ---- undo ----
print("\n[undo]")
let (restored, undoFailures) = organizer.undo(batch)
check("no undo failures", undoFailures.isEmpty, "\(undoFailures.map { $0.0.filename })")
check("all restored", restored.count == batch.operations.count)
for op in batch.operations {
    check("back at origin: \(op.source.lastPathComponent)",
          FileManager.default.fileExists(atPath: op.source.path))
}
check("decoy folder preserved (user content kept)",
      FileManager.default.fileExists(atPath: decoy.path))

// original top-level set should match what we started with
let afterUndo = Set((try! FileManager.default.contentsOfDirectory(at: sandbox, includingPropertiesForKeys: nil))
    .filter { !FileAnalyzer.isIgnored($0) }
    .map(\.lastPathComponent))
// Both the hidden file and the partial download are filtered from listings,
// so compare against the files Hoot actually surfaces.
let expected = Set(filenames.filter { $0 != ".DS_Store" && !$0.hasSuffix(".crdownload") })
check("partial download never touched",
      FileManager.default.fileExists(atPath: sandbox.appending(path: "big_download.crdownload").path))
check("top level restored exactly", afterUndo == expected, "\nextra: \(afterUndo.subtracting(expected))\nmissing: \(expected.subtracting(afterUndo))")

// ---- history persistence ----
print("\n[history]")
let store = sandbox.appending(path: "history.json")
let h1 = OperationHistory(storeURL: store)
h1.record(batch)
let h2 = OperationHistory(storeURL: store)
check("history survives reload", h2.batches.count == 1)
h2.markUndone(batch.id)
let h3 = OperationHistory(storeURL: store)
check("undone flag persists", h3.batches.first?.isUndone == true)
check("no undoable batch remains", h3.mostRecentUndoable == nil)
h3.clear()
check("clear empties the log", h3.batches.isEmpty)
check("cleared log stays empty after reload", OperationHistory(storeURL: store).batches.isEmpty)

// ---- regressions from a real Downloads folder ----
print("\n[real-world file types]")
let realNames = [
    "301847592_118273640591827_4472910385562931_n.jpg",  // no usable tokens
    "Beyond Vibe Coding -- Addy Osmani -- O\u{2019}Reilly.pdf",
    "DaVinci_Resolve_21.0.4_Mac.zip",
    "~$N Verification Slip.docx",                            // Office lock file
    " .png",                                                 // blank name, but real content
    " .tmp"                                                  // blank name and empty
]
let realDir = sandbox.appending(path: "real")
try! FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
for n in realNames {
    // The blank-named .tmp is written empty on purpose; everything else has content.
    let body = n == " .tmp" ? Data() : Data("x".utf8)
    try! body.write(to: realDir.appending(path: n))
}

let realURLs = try! FileManager.default.contentsOfDirectory(at: realDir, includingPropertiesForKeys: nil)
let realKept = realURLs.filter { !FileAnalyzer.isIgnored($0) }
check("Office lock file ignored", !realKept.contains { $0.lastPathComponent.hasPrefix("~$") })
check("blank name + empty file ignored", !realKept.contains { $0.lastPathComponent == " .tmp" })
check("blank name but real content is KEPT, not hidden",
      realKept.contains { $0.lastPathComponent == " .png" })
check("4 real files survive filtering", realKept.count == 4, "got \(realKept.map(\.lastPathComponent))")

let realFiles = realKept.compactMap { FileAnalyzer.analyze($0) }
var realCls: [UUID: ClassificationResult] = [:]
let rsem = DispatchSemaphore(value: 0)
Task {
    let c = RuleBasedClassifier()
    for f in realFiles { realCls[f.id] = try! await c.classify(f) }
    rsem.signal()
}
rsem.wait()

for f in realFiles {
    let r = realCls[f.id]!
    let expected: String
    switch f.fileExtension.lowercased() {
    case "jpg", "png": expected = "Images"
    case "pdf": expected = "Books"
    case "zip": expected = "Archives"
    default: expected = "?"
    }
    check("\(f.fileExtension) -> \(expected)", r.suggestedFolder == expected, "got \(r.suggestedFolder)")
    check("\(f.fileExtension) is actionable", !r.isLowConfidence, "conf \(r.confidence)")
}

print("\n[existing folders as taxonomy]")
let shelf = ExistingFolders(names: ["Books", "Finance", "School"])
check("exact match reuses user folder", shelf.canonicalName(for: "Books") == "Books")
check("synonym maps to user folder", shelf.canonicalName(for: "Ebooks") == "Books")
check("singular maps to plural folder", shelf.canonicalName(for: "Book") == "Books")
check("receipts map to Finance", shelf.canonicalName(for: "Receipts") == "Finance")
check("unrelated name left alone", shelf.canonicalName(for: "Cebu Trip") == "Cebu Trip")
check("no loose substring merging", shelf.canonicalName(for: "Homework") == "Homework")

stage3(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stage4(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stage5(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageSecurity(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageHardening(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stagePIM(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageEvidence(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageImages(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageConfidence(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageLearning(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageCloud(sandbox: sandbox, rawCheck: { check($0, $1, $2) })
stageCorrections(sandbox: sandbox, rawCheck: { check($0, $1, $2) })

try? FileManager.default.removeItem(at: sandbox)
print("\n\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")")
exit(failures == 0 ? 0 : 1)
