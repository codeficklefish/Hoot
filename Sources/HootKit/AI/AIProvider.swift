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

/// A name the provider thinks a file should have, as raw model output.
/// Nothing here is trusted yet — see `SuggestionValidator.sanitizeFilename`.
public struct NameSuggestion: Hashable {
    public init(
        filename: String,
        proposedName: String,
        reason: String,
        requestIndex: Int? = nil
    ) {
        self.filename = filename
        self.proposedName = proposedName
        self.reason = reason
        self.requestIndex = requestIndex
    }

    /// The file's current name, as the provider echoed it back.
    public let filename: String
    /// Which file in the request this answers, counting from 1.
    ///
    /// Filenames turned out to be a poor way to identify a file to a model.
    /// Asked to copy `------.txt` verbatim it returned `-----.txt`, one dash
    /// short — and the population this feature exists for is precisely the
    /// filenames that are hard to copy: runs of one character, long digit
    /// strings, keyboard mashes. A number survives the round trip.
    ///
    /// Optional because a provider is free not to number anything; matching
    /// falls back to the filename then.
    public let requestIndex: Int?
    public let proposedName: String
    /// One sentence saying what in the file's text the name came from.
    public let reason: String
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

    /// Proposes a name for each file whose current one says nothing.
    ///
    /// Only ever called with files that have a readable excerpt, because a
    /// name can only come from what is inside the file. A provider that
    /// cannot do this returns nothing and the files keep their names.
    func suggestNames(for files: [FileDescriptor]) async throws -> [NameSuggestion]
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

    /// Renaming is opt-in for a provider. Answering with nothing is a
    /// complete answer: every file keeps the name it arrived with, which is
    /// what a rule-based provider should do — it can only read the name, and
    /// the name is the thing that failed.
    public func suggestNames(for files: [FileDescriptor]) async throws -> [NameSuggestion] {
        []
    }
}

public enum ProviderAvailability: Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}
