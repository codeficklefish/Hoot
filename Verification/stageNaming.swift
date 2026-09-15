import Foundation
import HootKit

/// Renaming files whose names say nothing.
///
/// Every rule here guards the same thing: a name the user chose is never
/// touched, and a name Hoot invents comes only from text genuinely read out
/// of the file. Both failures are quiet ones — a wrongly renamed file looks
/// fine until someone goes looking for it under the name they gave it.
func stageNaming(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ l: String, _ ok: Bool, _ d: String = "") { rawCheck(l, ok, d) }

    // MARK: - Which names say nothing

    print("\n[which names say nothing]")

    func saysNothing(_ name: String) {
        check("meaningless: \(name)", MeaninglessName.applies(to: name))
    }
    func saysSomething(_ name: String) {
        check("left alone: \(name)", !MeaninglessName.applies(to: name))
    }

    saysNothing("32131231231.pdf")
    saysNothing("ASDFGHasdjhasg.png")
    saysNothing("------.zip")
    saysNothing("IMG_2948.jpg")
    saysNothing("DSC_0001.jpg")
    saysNothing("301847592_118273640591827_4472910385562931_n.jpg")
    saysNothing("a3f9c8e2d1b04f7a.bin")
    saysNothing("qwertyuiop.txt")
    saysNothing("untitled.docx")
    saysNothing(" .png")
    saysNothing("1.pdf")
    saysNothing("Screenshot 2026-01-02 at 3.45.10 PM.png")
    saysNothing("ASJKDHASDASD.txt")
    saysNothing("asjkdhasdasd.txt")

    // What actually lands in a Downloads folder: identifiers from social
    // media and CDNs. These are the hard ones — they carry vowels in
    // plausible places and no long consonant run, so the spelling rules
    // above read them as words unless something else catches them.
    saysNothing("HRzRhOQX0AgotkS.jpeg")
    saysNothing("FkQ2xZzWYAA1234.jpg")
    saysNothing("0f8a9b2c-3d4e-5f6a-7b8c-9d0e1f2a3b4c.png")
    saysNothing("photo_2024-01-15_12-34-56.jpg")

    // Real words that say only that nobody chose a name.
    saysNothing("unnamed.jpg")
    saysNothing("image.png")
    saysNothing("Document.pdf")
    saysNothing("download.zip")

    saysSomething("thesis_final.docx")
    saysSomething("invoice_march.pdf")
    saysSomething("Beyond Vibe Coding -- Addy Osmani -- O'Reilly.pdf")
    saysSomething("DaVinci_Resolve_21.0.4_Mac.zip")
    saysSomething("liberty statement.pdf")
    // The pair that made one threshold impossible: both carry a run of five
    // consonants. "strengths" carries it as a coda, the mash carries it in
    // the middle, and that is the only thing telling them apart.
    saysSomething("strengths.docx")
    saysSomething("twelfths.txt")
    saysSomething("warmths.txt")
    saysSomething("property.pdf")

    // Short acronyms are the trap: the tokenizer drops anything under three
    // characters and "NDA" has no vowels, so both of the obvious rules call
    // these gibberish and rename a document the user named deliberately.
    // The other side of those rules, each one a name someone chose.
    saysSomething("mp4box.dmg")            // a digit inside a product name
    saysSomething("jazz.mp3")              // a doubled rare letter
    saysSomething("pizza recipe.pdf")
    saysSomething("quiz answers.docx")
    saysSomething("Qatar trip.pdf")        // q not followed by u
    saysSomething("schedule.xlsx")         // a real three-consonant opening
    saysSomething("christmas list.txt")
    saysSomething("invoice2024.pdf")       // digits at the end, not buried
    saysSomething("covid19 results.pdf")

    saysSomething("CV.pdf")
    saysSomething("NDA.docx")
    saysSomething("W2.pdf")

    // MARK: - What a model may call a file

    print("\n[what a model may call a file]")

    func sanitized(_ proposed: String, _ original: String) -> String? {
        SuggestionValidator.sanitizeFilename(proposed, keepingExtensionOf: original)
    }

    check("keeps the file's own extension",
          sanitized("Delta boarding pass Manila", "32131231231.pdf")
            == "Delta boarding pass Manila.pdf",
          sanitized("Delta boarding pass Manila", "32131231231.pdf") ?? "nil")

    check("drops an extension the model added",
          sanitized("Delta boarding pass.pdf", "32131231231.pdf")
            == "Delta boarding pass.pdf",
          sanitized("Delta boarding pass.pdf", "32131231231.pdf") ?? "nil")

    check("never swaps the extension for one of its own",
          sanitized("Boarding pass.jpeg", "32131231231.pdf") == "Boarding pass.pdf",
          sanitized("Boarding pass.jpeg", "32131231231.pdf") ?? "nil")

    check("keeps a number that is part of the name",
          sanitized("Invoice 2024.03", "111.pdf") == "Invoice 2024.03.pdf",
          sanitized("Invoice 2024.03", "111.pdf") ?? "nil")

    check("a file with no extension stays that way",
          sanitized("Meeting notes", "8827361") == "Meeting notes",
          sanitized("Meeting notes", "8827361") ?? "nil")

    check("cannot escape its folder",
          sanitized("../../Escape", "111.pdf") == nil)
    check("cannot climb with a bare traversal",
          sanitized("..", "111.pdf") == nil)
    check("cannot hide the file",
          sanitized(".hidden receipt", "111.pdf") == nil)
    check("no path separators survive",
          sanitized("Receipts/March", "111.pdf") == nil)

    check("a colon is stripped rather than refused",
          sanitized("Receipt: March", "111.pdf") == "Receipt March.pdf",
          sanitized("Receipt: March", "111.pdf") ?? "nil")

    check("a placeholder is refused",
          sanitized("Untitled", "111.pdf") == nil)
    check("a name as meaningless as the old one is refused",
          sanitized("1234567", "111.pdf") == nil)
    check("repeating the current name is refused",
          sanitized("32131231231", "32131231231.pdf") == nil)
    check("an empty answer is refused",
          sanitized("", "111.pdf") == nil)
    check("whitespace alone is refused",
          sanitized("   ", "111.pdf") == nil)

    // Scanned paperwork is set in capitals and the model copies that casing
    // into the filename however firmly the prompt asks it not to.
    check("a name lifted from shouting paperwork is quietened",
          sanitized("DELTA AIR LINES BOARDING PASS", "111.pdf")
            == "Delta air lines boarding pass.pdf",
          sanitized("DELTA AIR LINES BOARDING PASS", "111.pdf") ?? "nil")
    check("a reference number keeps its shape",
          sanitized("INVOICE 2026-0447", "111.pdf") == "Invoice 2026-0447.pdf",
          sanitized("INVOICE 2026-0447", "111.pdf") ?? "nil")
    check("an acronym with no vowel keeps its capitals",
          sanitized("PHP 84500 RETAINER", "111.pdf") == "PHP 84500 retainer.pdf",
          sanitized("PHP 84500 RETAINER", "111.pdf") ?? "nil")
    // The known edge of the rule, written down rather than left to be
    // rediscovered: an acronym containing a vowel reads as a word.
    check("one that contains a vowel does not, and is sentence cased",
          sanitized("NDA ACME CORP", "111.pdf") == "Nda acme corp.pdf",
          sanitized("NDA ACME CORP", "111.pdf") ?? "nil")
    check("a name the model already cased is left alone",
          sanitized("Delta boarding pass Manila", "111.pdf")
            == "Delta boarding pass Manila.pdf")
    check("and one with a capitalised middle word keeps it",
          sanitized("Trip to Cebu", "111.pdf") == "Trip to Cebu.pdf",
          sanitized("Trip to Cebu", "111.pdf") ?? "nil")

    let runaway = String(repeating: "Quarterly report ", count: 20)
    let cut = sanitized(runaway, "111.pdf")
    check("a runaway name is cut to a usable length",
          (cut?.count ?? 999) <= 64, "\(cut?.count ?? -1)")
    check("and still ends in the right extension",
          cut?.hasSuffix(".pdf") == true, cut ?? "nil")

    // MARK: - Settings stored before renaming existed

    print("\n[a new setting does not disturb the old ones]")

    // The exact bytes a real installation had stored before this feature
    // existed. Synthesized decoding throws on the missing key, `load` falls
    // back to `.default` — and a person who had deliberately chosen
    // "Filename rules only" would silently be switched to the on-device
    // model on the first launch after updating. Settings quietly reverting
    // is indistinguishable from Hoot forgetting them for no reason.
    let storedBeforeRenaming = Data(
        #"{"provider":"rulesOnly","allowLocalContentReading":true}"#.utf8
    )
    let migrated = try? JSONDecoder().decode(AISettings.self, from: storedBeforeRenaming)

    check("settings saved before renaming existed still decode", migrated != nil)
    check("a chosen provider is not reset by the new key",
          migrated?.provider == .rulesOnly,
          migrated.map { "\($0.provider)" } ?? "nil")
    check("nor is content reading",
          migrated?.allowLocalContentReading == true)
    check("and renaming arrives switched off",
          migrated?.renameMeaninglessFiles == false)

    // Round trip, so the defensive decoding cannot rot into write-only code.
    let roundTripped = try? JSONDecoder().decode(
        AISettings.self,
        from: JSONEncoder().encode(
            AISettings(provider: .appleOnDevice,
                       allowLocalContentReading: false,
                       renameMeaninglessFiles: true)
        )
    )
    check("a saved setting comes back as it went in",
          roundTripped?.provider == .appleOnDevice
            && roundTripped?.allowLocalContentReading == false
            && roundTripped?.renameMeaninglessFiles == true)

    // MARK: - What the renamer asks, and what it accepts

    print("\n[what the renamer asks, and what it accepts]")

    let namingDir = sandbox.appending(path: "naming")
    try? FileManager.default.createDirectory(at: namingDir, withIntermediateDirectories: true)

    func makeFile(_ name: String) -> FileItem {
        let url = namingDir.appending(path: name)
        try? Data("x".utf8).write(to: url)
        return FileItem(url: url)!
    }

    let opaque = makeFile("32131231231.pdf")
    let chosen = makeFile("invoice_march.pdf")
    let picture = makeFile("IMG_4821.jpg")

    let readText = ExtractedEvidence(
        excerpt: "DELTA AIR LINES BOARDING PASS MANILA TO CEBU",
        isTextual: true
    )
    let guessedScene = ExtractedEvidence(
        excerpt: "appears to show: outdoor, sky, water",
        isTextual: false
    )
    let evidence: [UUID: ExtractedEvidence] = [
        opaque.id: readText,
        chosen.id: readText,
        picture.id: guessedScene
    ]
    let files = [opaque, chosen, picture]

    func propose(_ spy: NamingSpy) -> [UUID: ProposedName] {
        var result: [UUID: ProposedName] = [:]
        let done = DispatchSemaphore(value: 0)
        Task {
            result = await FileRenamer(provider: spy).proposeNames(for: files, evidence: evidence)
            done.signal()
        }
        done.wait()
        return result
    }

    let spy = NamingSpy(answer: { sent in
        sent.map {
            NameSuggestion(
                filename: $0.filename,
                proposedName: "Delta boarding pass Manila",
                reason: "The text reads DELTA AIR LINES BOARDING PASS."
            )
        }
    })
    let proposals = propose(spy)

    check("a meaningless name is renamed",
          proposals[opaque.id]?.name == "Delta boarding pass Manila.pdf",
          proposals[opaque.id]?.name ?? "nil")
    check("the reason the name was chosen is carried with it",
          proposals[opaque.id]?.reason.contains("DELTA") == true)

    check("a name the user chose is never even sent",
          !spy.received.contains { $0.filename == "invoice_march.pdf" })
    check("and is never renamed", proposals[chosen.id] == nil)

    check("a guess about a picture is not sent",
          !spy.received.contains { $0.filename == "IMG_4821.jpg" })
    check("and cannot become a name", proposals[picture.id] == nil)

    check("the file's own text is what gets sent",
          spy.received.first { $0.filename == "32131231231.pdf" }?.excerpt?
            .contains("DELTA AIR LINES") == true)

    // ---- a provider that is not local ----
    let remote = NamingSpy(isLocal: false, answer: { _ in [] })
    let fromRemote = propose(remote)
    check("a provider that is not local is shown nothing", remote.received.isEmpty)
    check("and is not asked at all", !remote.wasAsked)
    check("so nothing is renamed", fromRemote.isEmpty)

    // ---- a provider that fails ----
    let failing = NamingSpy(answer: { _ in throw AIProviderError.failed("simulated") })
    check("a provider that fails leaves every name alone", propose(failing).isEmpty)

    // ---- answers that do not match the request ----
    let liar = NamingSpy(answer: { _ in
        [NameSuggestion(filename: "somebody_elses_file.pdf",
                        proposedName: "Stolen name", reason: "")]
    })
    check("a name for a file that was never sent is dropped", propose(liar).isEmpty)

    let escaper = NamingSpy(answer: { sent in
        sent.map { NameSuggestion(filename: $0.filename,
                                  proposedName: "../../../etc/passwd", reason: "") }
    })
    check("a traversal dressed up as a name is dropped", propose(escaper).isEmpty)

    let echoer = NamingSpy(answer: { sent in
        sent.map { NameSuggestion(filename: $0.filename,
                                  proposedName: "32131231231", reason: "") }
    })
    check("the model repeating the current name means no rename", propose(echoer).isEmpty)

    // ---- identifying a file by number ----
    //
    // Asked to copy `------.txt` back verbatim, the real model returned it a
    // dash short and a good name was thrown away. The filenames this feature
    // exists for are exactly the ones that are hard to copy, so the answer
    // carries the file's number too.
    let miscopier = NamingSpy(answer: { sent in
        sent.enumerated().map { offset, file in
            NameSuggestion(
                filename: String(file.filename.dropLast(5)),   // mangled
                proposedName: "Delta boarding pass Manila",
                reason: "",
                requestIndex: offset + 1
            )
        }
    })
    check("a miscopied filename is recovered by its number",
          propose(miscopier)[opaque.id]?.name == "Delta boarding pass Manila.pdf",
          propose(miscopier)[opaque.id]?.name ?? "nil")

    let outOfRange = NamingSpy(answer: { _ in
        [NameSuggestion(filename: "nonsense.pdf", proposedName: "Stolen name",
                        reason: "", requestIndex: 99)]
    })
    check("a number outside the request is dropped", propose(outOfRange).isEmpty)

    let zeroIndex = NamingSpy(answer: { _ in
        [NameSuggestion(filename: "nonsense.pdf", proposedName: "Stolen name",
                        reason: "", requestIndex: 0)]
    })
    check("and so is a number below the first file", propose(zeroIndex).isEmpty)

    // The dangerous case: a number must never overrule an answer that named
    // its file outright, or a confident match could be replaced by a guess.
    let conflicting = NamingSpy(answer: { sent in
        [
            NameSuggestion(filename: sent[0].filename,
                           proposedName: "Named by its own filename", reason: ""),
            NameSuggestion(filename: "mangled",
                           proposedName: "Named by number instead", reason: "",
                           requestIndex: 1)
        ]
    })
    check("a number cannot take a file an exact name already claimed",
          propose(conflicting)[opaque.id]?.name == "Named by its own filename.pdf",
          propose(conflicting)[opaque.id]?.name ?? "nil")

    let greedy = NamingSpy(answer: { _ in
        [
            NameSuggestion(filename: "a", proposedName: "First answer",
                           reason: "", requestIndex: 1),
            NameSuggestion(filename: "b", proposedName: "Second answer",
                           reason: "", requestIndex: 1)
        ]
    })
    let greedyResult = propose(greedy)
    check("the same file cannot be named twice", greedyResult.count == 1)
    check("and the first answer is the one that stands",
          greedyResult[opaque.id]?.name == "First answer.pdf",
          greedyResult[opaque.id]?.name ?? "nil")
}

/// Stands in for a provider so the renamer's contract can be checked without
/// a model: what it was shown, whether it was asked at all, and what it does
/// with the answer.
final class NamingSpy: AIProvider, @unchecked Sendable {
    let displayName = "Spy"
    let isLocal: Bool

    private let answer: ([FileDescriptor]) throws -> [NameSuggestion]
    private(set) var received: [FileDescriptor] = []
    private(set) var wasAsked = false

    init(isLocal: Bool = true,
         answer: @escaping ([FileDescriptor]) throws -> [NameSuggestion]) {
        self.isLocal = isLocal
        self.answer = answer
    }

    func availability() async -> ProviderAvailability { .available }

    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        GroupingSuggestion(projects: [], loose: [])
    }

    func suggestNames(for files: [FileDescriptor]) async throws -> [NameSuggestion] {
        wasAsked = true
        received = files
        return try answer(files)
    }
}
