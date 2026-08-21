import Foundation

/// What Hoot tells a provider about one file. Deliberately narrow: a provider
/// only ever sees what the privacy rules allow, never the file itself.
public struct FileDescriptor: Hashable {
    public let id: UUID
    public let filename: String
    public let sizeDescription: String
    public let modifiedAt: Date?
    /// A short text excerpt, present only when the active provider runs
    /// locally and content reading is enabled.
    public let excerpt: String?
}

/// One project the provider believes exists, as raw model output.
/// Nothing here is trusted yet — see `SuggestionValidator`.
public struct ProjectSuggestion: Hashable {
    public init(name: String, filenames: [String], reason: String, confidence: Double) {
        self.name = name
        self.filenames = filenames
        self.reason = reason
        self.confidence = confidence
    }

    public let name: String
    public let filenames: [String]
    public let reason: String
    /// 0...1
    public let confidence: Double
}

public struct GroupingSuggestion: Hashable {
    public init(projects: [ProjectSuggestion], loose: [String]) {
        self.projects = projects
        self.loose = loose
    }

    public let projects: [ProjectSuggestion]
    public let loose: [String]
}

/// Where the provider thinks a single, unrelated file belongs.
public struct CategorySuggestion: Hashable {
    public init(filename: String, category: String, reason: String, confidence: Double) {
        self.filename = filename
        self.category = category
        self.reason = reason
        self.confidence = confidence
    }

    public let filename: String
    public let category: String
    public let reason: String
    /// 0...1
    public let confidence: Double
}

public enum AIProviderError: LocalizedError {
    case unavailable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "AI provider unavailable: \(why)"
        case .failed(let why): return "AI request failed: \(why)"
        }
    }
}

/// The swap-in point for intelligence. Hoot ships with an on-device provider;
/// Ollama and OpenAI-compatible providers slot in here without any other part
/// of the app changing.
public protocol AIProvider {
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
    public func prewarm() {}

    /// Providers that only do grouping fall back to rule-based categories.
    public func suggestCategories(
        for files: [FileDescriptor],
        preferredFolders: [String]
    ) async throws -> [CategorySuggestion] {
        []
    }
}

public enum ProviderAvailability: Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}
