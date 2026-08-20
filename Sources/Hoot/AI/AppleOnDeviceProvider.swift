import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Runs Apple's on-device language model. Nothing leaves the machine, there
/// is no API key, and no server needs to be installed — so this is the
/// provider Hoot prefers when the OS supports it.
@available(macOS 26.0, *)
struct AppleOnDeviceProvider: AIProvider {
    let displayName = "Apple Intelligence (on-device)"
    let isLocal = true

    /// The model handles a modest context, and long prompts slow it down, so
    /// large folders are grouped in chunks rather than one giant request.
    static let maximumFilesPerRequest = 18

    /// Filing decisions must be reproducible.
    ///
    /// The framework samples randomly by default, which for this task is
    /// actively harmful: running the same folder through Hoot five times
    /// produced accuracies from 33% to 66% with no code change at all, and
    /// the same photo landed in "Nature" one run and "Photography" the next.
    /// A user cannot build a mental model of a tool that answers differently
    /// each time — and it makes any measurement of quality meaningless.
    /// Greedy decoding always takes the most likely token, so the same input
    /// gives the same answer.
    private static let deterministic = GenerationOptions(sampling: .greedy)

    func availability() async -> ProviderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        @unknown default:
            return .unavailable(reason: "Unknown model state")
        }
    }

    /// The first request of a session pays for loading the model. Warming it
    /// while the user is still deciding whether to review keeps that cost off
    /// the path they actually wait on.
    func prewarm() {
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }

    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion {
        guard case .available = await availability() else {
            throw AIProviderError.unavailable("The on-device model isn't ready.")
        }

        var projects: [ProjectSuggestion] = []
        var loose: [String] = []

        for chunk in files.chunked(into: Self.maximumFilesPerRequest) {
            let result = try await suggest(chunk: chunk)
            projects.append(contentsOf: result.projects)
            loose.append(contentsOf: result.loose)
        }

        return GroupingSuggestion(projects: projects, loose: loose)
    }

    private func suggest(chunk: [FileDescriptor]) async throws -> GroupingSuggestion {
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let answer = try await session.respond(
                to: Self.prompt(for: chunk),
                generating: ModelGrouping.self,
                options: Self.deterministic
            )
            return GroupingSuggestion(
                projects: answer.content.projects.map {
                    ProjectSuggestion(
                        name: $0.name,
                        filenames: $0.filenames,
                        reason: $0.reason,
                        confidence: Double(max(0, min(100, $0.confidence))) / 100
                    )
                },
                loose: answer.content.loose
            )
        } catch {
            throw AIProviderError.failed(error.localizedDescription)
        }
    }

    func suggestCategories(
        for files: [FileDescriptor],
        preferredFolders: [String]
    ) async throws -> [CategorySuggestion] {
        guard case .available = await availability() else {
            throw AIProviderError.unavailable("The on-device model isn't ready.")
        }

        var suggestions: [CategorySuggestion] = []
        for chunk in files.chunked(into: Self.maximumFilesPerRequest) {
            let session = LanguageModelSession(
                instructions: Self.categoryInstructions(preferredFolders: preferredFolders)
            )
            do {
                let answer = try await session.respond(
                    to: Self.categoryPrompt(for: chunk),
                    generating: ModelCategories.self,
                    options: Self.deterministic
                )
                suggestions += answer.content.files.map {
                    CategorySuggestion(
                        filename: $0.filename,
                        category: $0.folder,
                        reason: $0.reason,
                        confidence: Double(max(0, min(100, $0.confidence))) / 100
                    )
                }
            } catch {
                throw AIProviderError.failed(error.localizedDescription)
            }
        }
        return suggestions
    }

    private static func categoryInstructions(preferredFolders: [String]) -> String {
        var text = """
        You decide which folder each downloaded file belongs in.

        Judge by what the file actually IS, using its name and the text taken from inside it. The text is the strongest evidence: a spreadsheet of tax records belongs with finance regardless of its filename, and an archive holding a single installer is software.

        For an image, words read out of the picture identify its subject far better than a description of the scene does. Decide from those words. Treat the scene description as a weak hint only, and never let it override words that were actually read. Do not borrow a folder name from these instructions.

        Rules:
        - Give a short, real folder name — a subject, not a file type.         Prefer "Finance" over "Spreadsheets", "Software" over "Archives".
        - Placeholder names such as "Misc", "Other", "Files" or "Untitled" are forbidden.
        - Every input filename must appear exactly once in your answer.
        - Copy filenames verbatim, including the extension.
        """
        if !preferredFolders.isEmpty {
            text += """

            The user already keeps these folders. Reuse one whenever the file             plausibly belongs there, instead of inventing a similar name:
            \(preferredFolders.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
        return text
    }

    private static func categoryPrompt(for files: [FileDescriptor]) -> String {
        var lines = ["Choose a folder for each of these \(files.count) files:"]
        for file in files {
            lines.append("- \(file.filename)")
            if let excerpt = file.excerpt, !excerpt.isEmpty {
                lines.append("    text from inside: \(excerpt)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Naming guidance is kept abstract on purpose: giving concrete example
    /// project names causes the model to reuse them verbatim for unrelated
    /// files instead of deriving a name from the files in front of it.
    private static let instructions = """
    You group a user's downloaded files into project folders.

    A project is a set of TWO OR MORE files a person would keep in one folder \
    because they belong to the same real-world piece of work, trip, event, \
    course, client, or recurring bill. Files belong together when they serve \
    one goal, even when their names look nothing alike.

    Naming a project:
    - Derive the name from the shared subject of THOSE SPECIFIC files, using \
    words that actually appear in their filenames.
    - Do not reuse a name from these instructions. Do not use placeholder \
    names such as "Project A", "Group 1", "Untitled" or "Miscellaneous".

    Hard rules:
    - Every project must list at least 2 filenames. Never make a project for one file.
    - A file with no clear companion goes in "loose".
    - Every input filename must appear exactly once, either in a project or in loose.
    - Copy filenames verbatim, including the extension.
    - When unsure, prefer loose over a weak grouping.
    """

    private static func prompt(for files: [FileDescriptor]) -> String {
        var lines = ["Group these \(files.count) files:"]
        for file in files {
            var line = "- \(file.filename)"
            if let excerpt = file.excerpt, !excerpt.isEmpty {
                line += "\n    opening text: \(excerpt)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This Mac doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off in System Settings."
        case .modelNotReady:
            return "The on-device model is still downloading."
        @unknown default:
            return "The on-device model isn't available."
        }
    }
}

// MARK: - Guided generation types

/// The shape the model must fill in. Asking for projects-with-filenames
/// (rather than a project field on each file) is what makes the model
/// actually reason about grouping instead of labelling files one by one.
@available(macOS 26.0, *)
@Generable
private struct ModelProject: Equatable {
    @Guide(description: "Short folder name in real words. Never a placeholder.")
    let name: String
    @Guide(description: "Every filename that belongs in this folder, copied verbatim. At least 2.")
    let filenames: [String]
    @Guide(description: "One short sentence on what connects these files")
    let reason: String
    @Guide(description: "Confidence from 0 to 100 that these files truly belong together")
    let confidence: Int
}

@available(macOS 26.0, *)
@Generable
private struct ModelCategory: Equatable {
    @Guide(description: "The filename, copied verbatim from the input")
    let filename: String
    @Guide(description: "Short subject-based folder name, e.g. Finance or Software. Never a placeholder.")
    let folder: String
    @Guide(description: "One short sentence citing the evidence used")
    let reason: String
    @Guide(description: "Confidence from 0 to 100")
    let confidence: Int
}

@available(macOS 26.0, *)
@Generable
private struct ModelCategories: Equatable {
    @Guide(description: "One entry for every input filename")
    let files: [ModelCategory]
}

@available(macOS 26.0, *)
@Generable
private struct ModelGrouping: Equatable {
    @Guide(description: "Projects, each containing 2 or more related files. Empty if nothing is clearly related.")
    let projects: [ModelProject]
    @Guide(description: "Filenames that belong to no project, copied verbatim")
    let loose: [String]
}

#endif

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
