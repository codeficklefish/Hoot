import Foundation

/// Turns raw model output into something safe to act on.
///
/// A language model's reply is untrusted input: the project names it invents
/// become real directory names, and the filenames it echoes back decide which
/// of the user's files get moved. Everything here is defensive — the model
/// gets to *suggest* groupings, never to name a path or nominate a file that
/// wasn't in the request.
public struct SuggestionValidator {
    public init() {}


    /// Names that carry no meaning and would produce junk folders, even
    /// though the prompt forbids them.
    private static let placeholders: Set<String> = [
        "untitled", "unnamed", "misc", "miscellaneous", "other", "others",
        "folder", "new folder", "files", "documents", "project", "projects",
        "group", "unsorted", "general", "stuff", "temp", "various"
    ]

    /// A single path component can't exceed 255 bytes on APFS; stay well under.
    private static let maximumNameLength = 60

    /// A project needs at least this many files to be worth a folder.
    private static let minimumFilesPerProject = 2

    public struct ValidatedProject {
        public let name: String
        public let files: [FileItem]
        public let reason: String
        public let confidence: Double
    }

    /// Matches a suggestion against the files that were actually sent, and
    /// discards anything unusable.
    ///
    /// - Returns: validated projects, plus every file that ended up in no
    ///   project (including ones the model never mentioned).
    /// - Parameter filesWithContent: files whose text the provider actually
    ///   read. Content is evidence in its own right; a filename is not.
    public func validate(
        _ suggestion: GroupingSuggestion,
        against files: [FileItem],
        filesWithContent: Set<UUID> = []
    ) -> (projects: [ValidatedProject], ungrouped: [FileItem]) {

        // Only files from this request may be referenced. Anything else the
        // model returns is a hallucination and is dropped.
        var byName: [String: FileItem] = [:]
        for file in files { byName[file.filename] = file }

        var claimed: Set<UUID> = []
        var projects: [ValidatedProject] = []
        var usedNames: Set<String> = []

        for project in suggestion.projects {
            guard let name = Self.sanitizeName(project.name) else { continue }

            // Resolve to real files, ignoring unknown names and any file a
            // previous project already claimed.
            var resolved: [FileItem] = []
            for filename in project.filenames {
                guard let file = byName[filename], !claimed.contains(file.id) else { continue }
                resolved.append(file)
                claimed.insert(file.id)
            }

            // A model asked to group will group. Left unchecked it sweeps in
            // files it knows nothing about — a camera-roll photo with no
            // readable name and no text inside has no business landing in
            // someone's "Software Development" folder. Require each member to
            // share something real with the project.
            let (supported, unsupported) = Self.partitionBySupport(
                resolved, projectName: name, filesWithContent: filesWithContent
            )
            unsupported.forEach { claimed.remove($0.id) }
            let members = supported

            // The model breaks the "two or more" rule often enough that it has
            // to be enforced here rather than trusted.
            guard members.count >= Self.minimumFilesPerProject else {
                members.forEach { claimed.remove($0.id) }
                continue
            }

            let uniqueName = Self.disambiguate(name, against: &usedNames)
            projects.append(
                ValidatedProject(
                    name: uniqueName,
                    files: members.sorted { $0.filename < $1.filename },
                    reason: Self.sanitizeReason(project.reason, fallback: "These files look related."),
                    confidence: min(max(project.confidence, 0), 1)
                )
            )
        }

        let ungrouped = files.filter { !claimed.contains($0.id) }
        return (projects, ungrouped)
    }

    /// Cleans a folder name the *user* typed.
    ///
    /// Kept separate from `sanitizeName`: that one also strips placeholder
    /// and filler words to compensate for model quirks, which would be
    /// patronising here — if someone deliberately names a folder "Documents"
    /// or "Misc", that's their call. Only genuinely unsafe path characters
    /// are removed.
    public static func sanitizeUserFolderName(_ raw: String) -> String? {
        var name = raw
        let forbidden = CharacterSet(charactersIn: "/\\:\u{0}").union(.controlCharacters)
        name = name.components(separatedBy: forbidden).joined(separator: " ")
        name = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.replacingOccurrences(of: "..", with: ".")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if name.count > maximumNameLength {
            name = String(name.prefix(maximumNameLength)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }

    /// Splits a proposed project's files into those with a real connection to
    /// it and those swept in on nothing.
    ///
    /// A file is supported when either:
    /// - the provider actually read text from inside it, so its placement can
    ///   rest on content rather than guesswork; or
    /// - its filename shares a distinctive word with the project name or with
    ///   another member, which is the same signal rule-based grouping uses.
    ///
    /// Images are the common casualty, and rightly so: there is no OCR, so a
    /// photo named `IMG_4821.jpg` carries no evidence whatsoever. Filing it
    /// under its type is honest; filing it under a guessed project buries it.
    private static func partitionBySupport(
        _ files: [FileItem],
        projectName: String,
        filesWithContent: Set<UUID>
    ) -> (supported: [FileItem], unsupported: [FileItem]) {

        let tokensByFile = Dictionary(uniqueKeysWithValues: files.map {
            ($0.id, Set(FilenameTokenizer.tokens(in: $0.filename)))
        })
        let projectTokens = Set(FilenameTokenizer.tokens(in: projectName))

        var supported: [FileItem] = []
        var unsupported: [FileItem] = []

        for file in files {
            if filesWithContent.contains(file.id) {
                supported.append(file)
                continue
            }

            let own = tokensByFile[file.id] ?? []
            let others = files
                .filter { $0.id != file.id }
                .reduce(into: Set<String>()) { $0.formUnion(tokensByFile[$1.id] ?? []) }

            if !own.isDisjoint(with: projectTokens) || !own.isDisjoint(with: others) {
                supported.append(file)
            } else {
                unsupported.append(file)
            }
        }

        return (supported, unsupported)
    }

    // MARK: - Sanitizing

    /// Reduces a model-supplied name to a safe single path component, or nil
    /// if nothing usable survives. Guards against path traversal, hidden
    /// files, separators, control characters and meaningless labels.
    public static func sanitizeName(_ raw: String) -> String? {
        var name = raw

        // Strip anything that could change where the folder lands.
        let forbidden = CharacterSet(charactersIn: "/\\:\u{0}").union(.controlCharacters)
        name = name.components(separatedBy: forbidden).joined(separator: " ")

        // Collapse whitespace and trim.
        name = name.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // A leading dot would hide the folder; repeated dots could traverse.
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.replacingOccurrences(of: "..", with: ".")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))

        guard !name.isEmpty else { return nil }
        guard !placeholders.contains(name.lowercased()) else { return nil }

        // Reject "Project A" / "Group 1" style names the prompt asked it to avoid.
        if name.range(of: #"^(project|group|folder|set)\s+([a-z]|\d+)$"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        // Models like to append a redundant noun ("Cebu Trip Files"), which
        // makes for a clumsy folder name. Drop it when something remains.
        for suffix in ["files", "file", "documents", "docs", "folder", "stuff", "items"] {
            let trailing = " " + suffix
            if name.lowercased().hasSuffix(trailing) {
                let trimmed = String(name.dropLast(trailing.count))
                    .trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !placeholders.contains(trimmed.lowercased()) {
                    name = trimmed
                }
                break
            }
        }

        if name.count > maximumNameLength {
            name = String(name.prefix(maximumNameLength)).trimmingCharacters(in: .whitespaces)
        }

        return name.isEmpty ? nil : name
    }

    private static func sanitizeReason(_ raw: String, fallback: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }
        return cleaned.count > 200 ? String(cleaned.prefix(200)) + "…" : cleaned
    }

    /// Two projects with the same name would merge into one folder, so later
    /// duplicates get a numeric suffix.
    private static func disambiguate(_ name: String, against used: inout Set<String>) -> String {
        let key = name.lowercased()
        guard used.contains(key) else {
            used.insert(key)
            return name
        }
        var counter = 2
        while used.contains("\(key) \(counter)") { counter += 1 }
        used.insert("\(key) \(counter)")
        return "\(name) \(counter)"
    }
}
