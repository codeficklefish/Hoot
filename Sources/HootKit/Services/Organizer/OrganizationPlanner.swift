import Foundation

/// Turns discovered files plus their classifications into a plan the user can
/// review. Project grouping wins over per-file category: a file that belongs
/// to a detected project goes in that project's folder, not in a type folder.
public struct OrganizationPlanner {
    public init() {}


    /// Bergman et al. (2010) timed 296 users navigating their own file
    /// systems and found a direct trade-off: each extra folder level costs
    /// about as much time as scanning ~21 extra items in a folder. So an
    /// extra level only pays for itself once it removes more than that many
    /// items from view.
    ///
    /// This is why Hoot stopped splitting every project into Documents/Data/
    /// Images: for a three-file trip folder those subfolders cost a level of
    /// depth and save nothing. It also avoids re-imposing exactly the
    /// format-based fragmentation that project grouping exists to undo.
    private static let subfolderWorthwhileThreshold = 21

    /// Where superseded versions go — visible, adjacent, but out of the way.
    public static let demotedSubfolder = "Previous Versions"


    /// Builds a plan from projects that have already been detected, so the
    /// planner stays independent of *how* they were found (rules or a model).
    public func makePlan(
        root: URL,
        detectedProjects: [DetectedProject],
        ungrouped: [FileItem],
        classifications: [UUID: ClassificationResult],
        preferences: FolderPreferences = FolderPreferences()
    ) -> OrganizationPlan {

        var skipped: [(file: FileItem, reason: String)] = []
        var groups: [PlannedGroup] = []

        // Folders the user already keeps here take precedence over invented
        // names, so files join an existing shelf instead of starting a rival one.
        let existing = ExistingFolders(in: root)

        /// Resolution order: what was proposed, then any name the user has
        /// previously corrected it to, then a folder they already keep.
        func resolveFolder(_ proposed: String) -> String {
            existing.canonicalName(for: preferences.preferredName(for: proposed))
        }

        // 1. Files that form a project keep their project together, with
        //    per-file subfolders by role (Documents / Data / Research…).
        for project in detectedProjects {
            var moves: [PlannedMove] = []

            // Superseded versions are demoted rather than deleted: the user
            // never has to make a keep-or-lose decision, but the current
            // version is the one they see first.
            let superseded = Set(
                VersionFamilies().families(in: project.files)
                    .flatMap { $0.superseded.map(\.id) }
            )
            let splitByRole = project.files.count > Self.subfolderWorthwhileThreshold

            for file in project.files {
                guard let classification = classifications[file.id] else { continue }
                let role: String?
                if superseded.contains(file.id) {
                    role = Self.demotedSubfolder
                } else if splitByRole {
                    role = Self.roleSubfolder(for: file, classification: classification)
                } else {
                    role = nil
                }
                moves.append(
                    PlannedMove(
                        file: file,
                        classification: classification,
                        destinationFolder: resolveFolder(project.name),
                        roleSubfolder: role,
                        destinationName: file.filename,
                        isApproved: true
                    )
                )
            }
            guard !moves.isEmpty else { continue }
            groups.append(
                PlannedGroup(
                    name: resolveFolder(project.name),
                    proposedName: project.name,
                    rationale: Self.rationale(for: project),
                    moves: moves
                )
            )
        }

        // 2. Everything else falls back to its own category — but only when the
        //    classifier was confident enough to be worth acting on.
        // Version families are computed across all loose files, since two
        // versions of a document can land in the same category folder.
        let supersededLooseFiles = Set(
            VersionFamilies().families(in: ungrouped).flatMap { $0.superseded.map(\.id) }
        )

        var byCategory: [String: [PlannedMove]] = [:]
        for file in ungrouped {
            guard let classification = classifications[file.id] else { continue }

            if classification.isLowConfidence {
                skipped.append((file, classification.reason))
                continue
            }

            let folder = resolveFolder(classification.suggestedFolder)
            byCategory[folder, default: []].append(
                PlannedMove(
                    file: file,
                    classification: classification,
                    destinationFolder: folder,
                    roleSubfolder: supersededLooseFiles.contains(file.id)
                        ? Self.demotedSubfolder : nil,
                    destinationName: classification.suggestedName,
                    isApproved: true
                )
            )
        }

        for (category, moves) in byCategory.sorted(by: { $0.key < $1.key }) {
            groups.append(
                PlannedGroup(
                    name: category,
                    proposedName: category,
                    rationale: existing.allNames.contains(category)
                        ? "Filed into your existing “\(category)” folder."
                        : "Grouped by category — no shared project detected.",
                    moves: moves.sorted { $0.file.filename < $1.file.filename }
                )
            )
        }

        return OrganizationPlan(root: root, groups: groups, skipped: skipped)
    }

    /// Builds a plan that files everything by type, with no interpretation.
    ///
    /// Shares nothing with `makePlan` beyond the shape of its result, which
    /// is the point: there are no projects to detect, no confidence to weigh
    /// and no model to wait for. A file's folder follows from its name and
    /// extension, so this returns in the time it takes to loop over them.
    ///
    /// It still honours the two things the user has said out loud — folders
    /// they already keep, and names they have corrected before — because
    /// those are their decisions, not Hoot's inferences.
    public func makeTypePlan(
        root: URL,
        files: [FileItem],
        preferences: FolderPreferences = FolderPreferences()
    ) -> OrganizationPlan {

        let existing = ExistingFolders(in: root)
        func resolveFolder(_ proposed: String) -> String {
            existing.canonicalName(for: preferences.preferredName(for: proposed))
        }

        var skipped: [(file: FileItem, reason: String)] = []
        var byFolder: [String: [PlannedMove]] = [:]
        // The name Hoot proposed before the user's own vocabulary was applied,
        // kept so a rename here can be remembered the same way it is anywhere
        // else: "when you say Images, I mean Photos".
        var proposedNames: [String: String] = [:]

        for file in files {
            guard let bucket = TypeSorter.folder(for: file) else {
                skipped.append((file, "Hoot doesn’t recognize .\(file.fileExtension) files, so this one stays where it is."))
                continue
            }

            let folder = resolveFolder(bucket)
            proposedNames[folder] = bucket

            byFolder[folder, default: []].append(
                PlannedMove(
                    file: file,
                    classification: ClassificationResult(
                        fileID: file.id,
                        category: bucket,
                        project: nil,
                        suggestedFolder: folder,
                        suggestedName: file.filename,
                        // The extension is the evidence, and it is the only
                        // evidence. Nothing was read, so nothing else can
                        // corroborate it — and nothing needs to.
                        confidence: ConfidenceModel.combine([.recognizedType]),
                        reason: TypeSorter.reason(for: file)
                    ),
                    destinationFolder: folder,
                    // Flat on purpose. Someone who asked not to have their
                    // files interpreted has not asked for a folder tree either.
                    roleSubfolder: nil,
                    destinationName: file.filename,
                    isApproved: true
                )
            )
        }

        let groups = byFolder
            .sorted { $0.key < $1.key }
            .map { folder, moves in
                PlannedGroup(
                    name: folder,
                    proposedName: proposedNames[folder] ?? folder,
                    rationale: existing.allNames.contains(folder)
                        ? "Filed into your existing “\(folder)” folder, by type."
                        : "Sorted by file type.",
                    moves: moves.sorted { $0.file.filename < $1.file.filename }
                )
            }

        return OrganizationPlan(root: root, groups: groups, skipped: skipped)
    }

    /// Within a project folder, split files by the role they play.
    private static func roleSubfolder(for file: FileItem, classification: ClassificationResult) -> String? {
        switch classification.category {
        case "Data": return "Data"
        case "Research": return "Research"
        default: break
        }
        switch file.kind {
        case .spreadsheet: return "Data"
        case .image: return "Images"
        case .pdf, .document, .text: return "Documents"
        case .book: return "Books"
        case .media: return "Media"
        case .archive, .installer, .other: return nil
        }
    }

    private static func rationale(for project: DetectedProject) -> String {
        let percent = Int(project.confidence * 100)
        switch project.source {
        case .rules:
            return "\(project.rationale) (\(percent)% match)"
        case .ai(let providerName):
            return "\(project.rationale) — \(providerName), \(percent)% confident"
        }
    }
}
