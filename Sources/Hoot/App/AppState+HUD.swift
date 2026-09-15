import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// The HUD's side of the app: turning the current plan into something that
/// can be answered one folder at a time, and carrying out each answer.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    /// The groups the HUD walks through, built from the plan.
    ///
    /// Only approved moves. A move the user unticked in the review window is
    /// not going to happen, and offering it again at the notch would be the
    /// two surfaces disagreeing about what was decided.
    var tidyGroups: [TidyGroup] {
        guard let plan else { return [] }
        return plan.groups.compactMap { group in
            let files = group.moves.filter(\.isApproved).map { move in
                TidyFile(
                    moveID: move.id,
                    currentName: move.file.filename,
                    proposedName: move.destinationName == move.file.filename
                        ? nil : move.destinationName,
                    kindSymbol: move.file.kind.symbolName,
                    // When it turned up, for the tray's "oldest 3h". Created
                    // rather than modified: a download that was edited after
                    // it arrived has not been waiting any less long.
                    addedAt: move.file.createdAt ?? move.file.modifiedAt
                )
            }
            guard !files.isEmpty else { return nil }
            return TidyGroup(name: group.name, reason: group.rationale, files: files)
        }
    }

    /// Starts a fresh walk through the current plan, or clears it when there
    /// is nothing to file.
    func refreshTidyFlow() {
        let groups = tidyGroups
        guard !groups.isEmpty else { return tidyFlow = nil }

        // Leave a walk already in progress alone: rebuilding it under the
        // person mid-decision would move the goalposts between reading a
        // group and answering it.
        if let existing = tidyFlow, existing.groups == groups { return }
        tidyFlow = TidyFlow(
            groups: groups,
            isRenaming: settings.renameMeaninglessFiles,
            // Carried so the tray can account for the whole folder rather
            // than only the part of it the walk is about.
            leftAlone: plan?.skipped.count ?? 0
        )
    }

    func toggleTidyFile(_ fileID: UUID) {
        tidyFlow?.toggle(fileID)
    }

    func toggleTidyRenaming() {
        tidyFlow?.isRenaming.toggle()
    }

    func skipTidyGroup() {
        tidyFlow?.skip()
    }

    // MARK: - Moving between folders
    //
    // Looking is not answering. These change which folder the panel is
    // showing and nothing else — no file moves, and the folder that was on
    // screen is still waiting when you come back to it.

    func showNextTidyGroup() {
        tidyFlow?.showNext()
    }

    func showPreviousTidyGroup() {
        tidyFlow?.showPrevious()
    }

    func showTidyGroup(at index: Int) {
        tidyFlow?.show(groupAt: index)
    }

    /// Files the current group's kept files, one at a time.
    ///
    /// Per file rather than in one call so the progress bar means something:
    /// it fills as files actually land. The operations are then recorded as
    /// a single batch, so undo takes the whole folder back rather than
    /// leaving the user to press it once per file.
    func applyTidyGroup() async {
        guard let root = watchedFolder, let flow = tidyFlow else { return }
        let kept = flow.keptFiles
        guard !kept.isEmpty, let currentPlan = plan else { return }

        let movesByID = Dictionary(
            uniqueKeysWithValues: currentPlan.allMoves.map { ($0.id, $0) }
        )
        let renaming = flow.isRenaming

        isTidyWorking = true
        tidyProgress = 0
        defer { isTidyWorking = false; tidyProgress = 0 }

        var operations: [FileOperation] = []
        var renamed = 0

        for (index, file) in kept.enumerated() {
            guard var move = movesByID[file.moveID] else { continue }

            // The chip decides whether the new name travels with the move.
            // Turning it off is not "leave the file where it is" — it is
            // "file it, but leave it called what it is called".
            if !renaming { move.destinationName = move.file.filename }
            move.isApproved = true
            let isRename = move.destinationName != move.file.filename

            let (batch, failures) = organizer.organize(
                OrganizationPlan(
                    root: root,
                    groups: [PlannedGroup(
                        name: move.destinationFolder,
                        proposedName: move.destinationFolder,
                        rationale: "Filed from the HUD.",
                        moves: [move]
                    )],
                    skipped: []
                )
            )

            operations += batch.operations
            if !batch.operations.isEmpty, isRename { renamed += 1 }

            for (failed, error) in failures {
                report(
                    UserFacingIssue(
                        title: "Couldn't file “\(failed.file.filename)”.",
                        suggestion: (error as? OrganizerError).map { organizerAdvice(for: $0) }
                            ?? error.localizedDescription
                    ),
                    underlying: error
                )
            }

            tidyProgress = Double(index + 1) / Double(kept.count)
            // Let the bar redraw between files rather than after all of them.
            await Task.yield()
        }

        if !operations.isEmpty {
            let batch = OperationBatch(
                id: UUID(),
                performedAt: Date(),
                rootFolder: root,
                operations: operations,
                undoneAt: nil
            )
            history.record(batch)
            batches = history.batches
            tidyBatches.append(batch)

            let movedURLs = Set(operations.map(\.source))
            detectedFiles.removeAll { movedURLs.contains($0.url) }
        }

        tidyFlow?.recordApplied(movedFiles: operations.count, renamedFiles: renamed)
    }

    /// Takes back everything this walk did, and starts it again.
    func undoTidy() {
        for batch in tidyBatches.reversed() { undo(batch) }
        tidyBatches.removeAll()
        tidyFlow?.restart()
        Task { await buildPlan(force: true) }
    }

    /// Ends the walk. The plan is rebuilt so the review window and the HUD
    /// agree about what is left in the folder.
    func finishTidy() {
        tidyFlow = nil
        tidyBatches.removeAll()
        plan = nil
        planSignature = nil
        Task { await buildPlan() }
    }
}
