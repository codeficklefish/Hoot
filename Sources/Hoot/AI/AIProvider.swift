import Foundation

/// What Hoot tells a provider about one file. Deliberately narrow: a provider
/// only ever sees what the privacy rules allow, never the file itself.
struct FileDescriptor: Hashable {
    let id: UUID
    let filename: String
    let sizeDescription: String
    let modifiedAt: Date?
    /// A short text excerpt, present only when the active provider runs
    /// locally and content reading is enabled.
    let excerpt: String?
}

/// One project the provider believes exists, as raw model output.
/// Nothing here is trusted yet — see `SuggestionValidator`.
struct ProjectSuggestion: Hashable {
    let name: String
    let filenames: [String]
    let reason: String
    /// 0...1
    let confidence: Double
}

struct GroupingSuggestion: Hashable {
    let projects: [ProjectSuggestion]
    let loose: [String]
}

/// Where the provider thinks a single, unrelated file belongs.
struct CategorySuggestion: Hashable {
    let filename: String
    let category: String
    let reason: String
    /// 0...1
    let confidence: Double
}

enum AIProviderError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "AI provider unavailable: \(why)"
        case .failed(let why): return "AI request failed: \(why)"
        }
    }
}

/// The swap-in point for intelligence. Hoot ships with an on-device provider;
/// Ollama and OpenAI-compatible providers slot in here without any other part
/// of the app changing.
protocol AIProvider {
    /// Shown in Settings.
    var displayName: String { get }

    /// True when inference happens on this machine and nothing is transmitted.
    /// Only local providers are ever handed file content — external providers
    /// receive filenames and metadata alone.
    var isLocal: Bool { get }

    /// Whether the provider can serve requests right now.
    func availability() async -> ProviderAvailability

    /// Proposes how the given files group into projects.
    func suggestGrouping(for files: [FileDescriptor]) async throws -> GroupingSuggestion

    /// Loads the model ahead of the first real request, if that helps.
    func prewarm()

    /// Proposes a folder for files that belong to no project.
    ///
    /// `preferredFolders` are folders the user already keeps, which the
    /// provider should reuse rather than inventing near-duplicates.
    func suggestCategories(
        for files: [FileDescriptor],
        preferredFolders: [String]
    ) async throws -> [CategorySuggestion]
}

extension AIProvider {
    /// Gives a provider the chance to load its model before it's needed.
    /// Optional: providers with no warm-up cost simply don't implement it.
    func prewarm() {}

    /// Providers that only do grouping fall back to rule-based categories.
    func suggestCategories(
        for files: [FileDescriptor],
        preferredFolders: [String]
    ) async throws -> [CategorySuggestion] {
        []
    }
}

enum ProviderAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }
}
