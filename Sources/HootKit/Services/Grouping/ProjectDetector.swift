import Foundation

/// A project Hoot believes exists, whoever worked it out.
public struct DetectedProject {
    public init(name: String, files: [FileItem], rationale: String,
                confidence: Double, source: Source) {
        self.name = name
        self.files = files
        self.rationale = rationale
        self.confidence = confidence
        self.source = source
    }

    public let name: String
    public let files: [FileItem]
    public let rationale: String
    public let confidence: Double
    public let source: Source

    public enum Source {
        case rules
        case ai(providerName: String)
    }
}

/// Decides which files belong together, and how the decision was reached.
public protocol ProjectDetecting {
    func detectProjects(in files: [FileItem]) async -> (projects: [DetectedProject], ungrouped: [FileItem])
}

/// Filename-token grouping. Always available, never uses a model — this is
/// both the no-AI default and the safety net when a provider fails.
public struct RuleBasedProjectDetector: ProjectDetecting {
    private let grouper = ProjectGrouper()

    public init() {}

    public func detectProjects(in files: [FileItem]) async -> (projects: [DetectedProject], ungrouped: [FileItem]) {
        let (groups, ungrouped) = grouper.group(files)
        let projects = groups.map { group in
            DetectedProject(
                name: group.name,
                files: group.files,
                rationale: group.sharedToken.map {
                    "\(group.files.count) files share “\($0)” in their names."
                } ?? "\(group.files.count) related files.",
                confidence: group.cohesion,
                source: .rules
            )
        }
        return (projects, ungrouped)
    }
}

/// Asks a model to find projects, then verifies everything it says.
///
/// Two guarantees hold no matter what the model returns:
/// file content is only ever handed to providers running on this machine,
/// and any failure falls back to rule-based grouping rather than blocking
/// the user or silently producing nothing.
public struct AIProjectDetector: ProjectDetecting {
    public let provider: AIProvider
    public let allowContentReading: Bool
    public let fallback: ProjectDetecting

    private let validator = SuggestionValidator()
    private let extractor: TextExtracting

    public init(
        provider: AIProvider,
        extractor: TextExtracting,
        allowContentReading: Bool,
        fallback: ProjectDetecting = RuleBasedProjectDetector()
    ) {
        self.provider = provider
        self.extractor = extractor
        self.allowContentReading = allowContentReading
        self.fallback = fallback
    }

    public func detectProjects(in files: [FileItem]) async -> (projects: [DetectedProject], ungrouped: [FileItem]) {
        guard files.count > 1 else { return ([], files) }

        guard case .available = await provider.availability() else {
            NSLog("Hoot: \(provider.displayName) unavailable, using rules instead.")
            return await fallback.detectProjects(in: files)
        }

        let descriptors = files.map(descriptor(for:))
        // Only files with genuine text inside may join a project on content
        // alone. An impression of what a photo depicts is shown to the model
        // as useful context, but it isn't grounds for membership.
        let withContent = Set(
            files.filter { extractor.evidence(for: $0)?.isTextual == true }.map(\.id)
        )

        do {
            let suggestion = try await provider.suggestGrouping(for: descriptors)
            let (validated, ungrouped) = validator.validate(
                suggestion, against: files, filesWithContent: withContent
            )

            // A model that returns nothing usable is no better than no model;
            // fall back rather than reporting "no projects found".
            guard !validated.isEmpty else {
                return await fallback.detectProjects(in: files)
            }

            let projects = validated.map {
                DetectedProject(
                    name: $0.name,
                    files: $0.files,
                    rationale: $0.reason,
                    confidence: $0.confidence,
                    source: .ai(providerName: provider.displayName)
                )
            }
            return (projects, ungrouped)
        } catch {
            NSLog("Hoot: \(provider.displayName) failed (\(error.localizedDescription)); using rules instead.")
            return await fallback.detectProjects(in: files)
        }
    }

    /// Builds what the provider is allowed to know about a file. File content
    /// is attached only for local providers, and only with the user's consent.
    private func descriptor(for file: FileItem) -> FileDescriptor {
        let mayReadContent = provider.isLocal && allowContentReading
        return FileDescriptor(
            id: file.id,
            filename: file.filename,
            sizeDescription: file.displaySize,
            modifiedAt: file.modifiedAt,
            excerpt: mayReadContent ? extractor.excerpt(for: file) : nil
        )
    }
}
