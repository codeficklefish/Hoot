import Foundation
import HootKit
import HootPlatformMac

// ===== Stage 3 checks: untrusted model output must never escape sandboxing =====

func stage3(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    func check(_ label: String, _ ok: Bool, _ detail: String = "") { rawCheck(label, ok, detail) }
    // Real files to validate against
    let names = ["thesis_final.docx", "survey_results.xlsx", "invoice.pdf", "cat.png"]
    for n in names { try? Data("x".utf8).write(to: sandbox.appending(path: n)) }
    let files = names.compactMap { FileAnalyzer.analyze(sandbox.appending(path: $0)) }

    let validator = SuggestionValidator()

    print("\n[validator: name sanitizing]")
    // Path traversal and separators must never survive into a folder name.
    let hostile: [(String, String?)] = [
        ("../../Escape", "Escape"),
        ("/etc/passwd", "etc passwd"),
        ("Thesis/Documents", "Thesis"),   // separator stripped, then redundant suffix dropped
        (".hidden", "hidden"),
        ("..", nil),
        ("", nil),
        ("   ", nil),
        ("Miscellaneous", nil),
        ("Project A", nil),
        ("Group 1", nil),
        ("Untitled", nil),
        ("Normal Name", "Normal Name"),
        ("Cebu Trip Files", "Cebu Trip"),
        ("Thesis Documents", "Thesis"),
        ("Files", nil),
    ]
    for (input, expected) in hostile {
        let got = SuggestionValidator.sanitizeName(input)
        check("sanitize \(input.isEmpty ? "<empty>" : input) -> \(expected ?? "rejected")",
              got == expected, "got \(got.map { "\"\($0)\"" } ?? "nil")")
    }
    let long = SuggestionValidator.sanitizeName(String(repeating: "A", count: 400))
    check("overlong name truncated", (long?.count ?? 999) <= 60, "len \(long?.count ?? -1)")
    check("no separator survives sanitizing",
          !(SuggestionValidator.sanitizeName("a/b\\c:d") ?? "").contains(where: { "/\\:".contains($0) }))

    print("\n[validator: file matching]")
    // Hallucinated filenames must be dropped, not moved.
    let hallucinated = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Ghost", filenames: ["does_not_exist.pdf", "also_fake.docx"],
                          reason: "made up", confidence: 0.99)
    ], loose: [])
    let (ghostProjects, ghostUngrouped) = validator.validate(hallucinated, against: files)
    check("hallucinated files produce no project", ghostProjects.isEmpty, "\(ghostProjects.map(\.name))")
    check("all real files remain ungrouped", ghostUngrouped.count == files.count)

    // Single-file "projects" must be demoted even though the prompt forbids them.
    let singleton = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Solo", filenames: ["invoice.pdf"], reason: "one file", confidence: 0.99)
    ], loose: [])
    let (soloProjects, soloUngrouped) = validator.validate(singleton, against: files)
    check("single-file project rejected", soloProjects.isEmpty)
    check("its file returned to ungrouped", soloUngrouped.contains { $0.filename == "invoice.pdf" })

    // A file claimed twice must land in exactly one project.
    let doubled = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Thesis", filenames: ["thesis_final.docx", "survey_results.xlsx"],
                          reason: "a", confidence: 0.9),
        ProjectSuggestion(name: "Thesis Extra", filenames: ["thesis_final.docx", "invoice.pdf"],
                          reason: "b", confidence: 0.9)
    ], loose: [])
    // Treat every file as readable so this case isolates duplicate handling.
    let allReadable = Set(files.map(\.id))
    let (dupProjects, dupUngrouped) = validator.validate(
        doubled, against: files, filesWithContent: allReadable)
    let placements = dupProjects.flatMap { $0.files.map(\.filename) }
    check("no file appears in two projects",
          Set(placements).count == placements.count, "\(placements)")
    check("second project demoted (only 1 valid file left)", dupProjects.count == 1, "\(dupProjects.map(\.name))")
    check("displaced file returned to ungrouped", dupUngrouped.contains { $0.filename == "invoice.pdf" })

    // Duplicate project names must not collapse into one folder.
    let sameName = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Work", filenames: ["thesis_final.docx", "survey_results.xlsx"], reason: "a", confidence: 0.9),
        ProjectSuggestion(name: "work", filenames: ["invoice.pdf", "cat.png"], reason: "b", confidence: 0.9)
    ], loose: [])
    let (namedProjects, _) = validator.validate(
        sameName, against: files, filesWithContent: Set(files.map(\.id)))
    check("duplicate project names disambiguated",
          Set(namedProjects.map(\.name)).count == namedProjects.count, "\(namedProjects.map(\.name))")

    // Every input file must be accounted for, even if the model ignores some.
    let partial = GroupingSuggestion(projects: [
        ProjectSuggestion(name: "Pair", filenames: ["thesis_final.docx", "survey_results.xlsx"], reason: "a", confidence: 0.9)
    ], loose: [])
    let (pProjects, pUngrouped) = validator.validate(
        partial, against: files, filesWithContent: Set(files.map(\.id)))
    let accounted = pProjects.flatMap { $0.files.map(\.filename) } + pUngrouped.map(\.filename)
    check("every file accounted for exactly once",
          Set(accounted) == Set(names) && accounted.count == names.count, "\(accounted)")

    print("\n[fallback behaviour]")
    let sem = DispatchSemaphore(value: 0)
    Task {
        // A provider that always fails must still yield rule-based grouping.
        let detector = AIProjectDetector(provider: FailingProvider(), extractor: MacPlatform.makeTextExtractor(), allowContentReading: false)
        let thesisFiles = ["thesis_a.docx", "thesis_b.docx"].compactMap { name -> FileItem? in
            try? Data("x".utf8).write(to: sandbox.appending(path: name))
            return FileAnalyzer.analyze(sandbox.appending(path: name))
        }
        let (projects, _) = await detector.detectProjects(in: thesisFiles)
        check("failing provider falls back to rules",
              projects.contains { $0.name == "Thesis" }, "\(projects.map(\.name))")
        if let p = projects.first {
            if case .rules = p.source { check("fallback marked as rule-sourced", true, "") }
            else { check("fallback marked as rule-sourced", false, "marked as AI") }
        }

        // An unavailable provider must not be consulted at all.
        let unavailable = AIProjectDetector(provider: UnavailableProvider(), extractor: MacPlatform.makeTextExtractor(), allowContentReading: false)
        let (up, _) = await unavailable.detectProjects(in: thesisFiles)
        check("unavailable provider falls back", up.contains { $0.name == "Thesis" })

        print("\n[privacy boundary]")
        // A remote provider must never receive file excerpts.
        let spy = SpyProvider(isLocal: false)
        _ = await AIProjectDetector(provider: spy, extractor: MacPlatform.makeTextExtractor(), allowContentReading: true)
            .detectProjects(in: thesisFiles)
        check("remote provider gets NO excerpts",
              spy.received.allSatisfy { $0.excerpt == nil },
              "leaked \(spy.received.filter { $0.excerpt != nil }.count)")

        // A local provider may, but only with consent.
        let localDenied = SpyProvider(isLocal: true)
        _ = await AIProjectDetector(provider: localDenied, extractor: MacPlatform.makeTextExtractor(), allowContentReading: false)
            .detectProjects(in: thesisFiles)
        check("local provider gets no excerpts when disabled",
              localDenied.received.allSatisfy { $0.excerpt == nil })

        sem.signal()
    }
    sem.wait()
}

// MARK: - Test doubles

struct FailingProvider: AIProvider {
    let displayName = "Failing"
    let isLocal = true
    func availability() async -> ProviderAvailability { .available }
    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        throw AIProviderError.failed("simulated")
    }
}

struct UnavailableProvider: AIProvider {
    let displayName = "Offline"
    let isLocal = true
    func availability() async -> ProviderAvailability { .unavailable(reason: "simulated") }
    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        throw AIProviderError.unavailable("should never be called")
    }
}

final class SpyProvider: AIProvider, @unchecked Sendable {
    let displayName = "Spy"
    let isLocal: Bool
    private(set) var received: [FileDescriptor] = []
    init(isLocal: Bool) { self.isLocal = isLocal }
    func availability() async -> ProviderAvailability { .available }
    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        received = files
        return GroupingSuggestion(projects: [], loose: files.map(\.filename))
    }
}
