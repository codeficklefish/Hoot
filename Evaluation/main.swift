import Foundation
import HootKit
import HootPlatformMac
import Hoot

// Ground truth: the folder the user themselves put each file in.
let downloads = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
let fm = FileManager.default
var labelled: [(file: FileItem, trueFolder: String)] = []
for entry in (try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
    guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
    for f in (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? [] {
        guard !FileAnalyzer.isIgnored(f), let item = FileAnalyzer.analyze(f) else { continue }
        labelled.append((item, entry.lastPathComponent))
    }
}
print("labelled files: \(labelled.count)")
let userFolders = Set(labelled.map(\.trueFolder)).sorted()
print("your folders: \(userFolders.joined(separator: ", "))\n")

let sem = DispatchSemaphore(value: 0)
Task {
    let rules = RuleBasedClassifier()
    let extractor = MacPlatform.makeTextExtractor()

    var rows: [(name: String, truth: String, rulePred: String, ruleConf: Double,
                aiPred: String, finalConf: Double, evidence: String)] = []

    // Rules with content, as the app runs them.
    var base: [UUID: ClassificationResult] = [:]
    var excerptFor: [UUID: String] = [:]
    for (f, _) in labelled {
        let ex = extractor.excerpt(for: f)
        if let ex { excerptFor[f.id] = ex }
        base[f.id] = rules.classify(f, excerpt: ex)
    }

    // AI refinement, given the user's own folders as candidates.
    var refined: [UUID: ClassificationResult] = [:]
    if let provider = MacPlatform.makeAIProvider(for: .default) {
        refined = await CategoryRefiner(provider: provider, extractor: MacPlatform.makeTextExtractor(), allowContentReading: true)
            .refine(labelled.map(\.file), existing: base, preferredFolders: userFolders)
    }

    for (f, truth) in labelled {
        let r = base[f.id]!
        let final = refined[f.id] ?? r
        rows.append((String(f.filename.prefix(34)), truth, r.suggestedFolder, r.confidence,
                     final.suggestedFolder, final.confidence,
                     excerptFor[f.id] == nil ? "name only" : "content"))
    }

    print("file                               | you        | rules      | +AI        | conf | evidence")
    print(String(repeating: "-", count: 100))
    var correct = 0
    var confSum = 0.0
    for r in rows.sorted(by: { $0.truth < $1.truth }) {
        let hit = r.aiPred.lowercased() == r.truth.lowercased()
        if hit { correct += 1 }
        confSum += r.finalConf
        print("\(r.name.padding(toLength: 34, withPad: " ", startingAt: 0)) | "
            + "\(r.truth.prefix(10).padding(toLength: 10, withPad: " ", startingAt: 0)) | "
            + "\(r.rulePred.prefix(10).padding(toLength: 10, withPad: " ", startingAt: 0)) | "
            + "\(r.aiPred.prefix(10).padding(toLength: 10, withPad: " ", startingAt: 0)) | "
            + "\(Int(r.finalConf * 100))%".padding(toLength: 4, withPad: " ", startingAt: 0) + " | "
            + "\(hit ? "OK " : "MISS") \(r.evidence)")
    }
    let acc = Double(correct) / Double(rows.count)
    print("\nexact-match accuracy: \(correct)/\(rows.count) = \(Int(acc * 100))%")
    print("mean claimed confidence: \(Int(confSum / Double(rows.count) * 100))%")
    print("=> overconfidence gap: \(Int((confSum / Double(rows.count) - acc) * 100)) points")
    sem.signal()
}
sem.wait()
