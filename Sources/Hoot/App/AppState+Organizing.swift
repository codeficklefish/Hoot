import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// Carrying out an approved plan, and taking it back.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    /// Executes the approved moves in the current plan.
    func organizeApproved() {
        guard let current = plan else { return }
        let approved = current.approvedMoves
        guard !approved.isEmpty else { return }

        let (batch, failures) = organizer.organize(current)

        if !batch.operations.isEmpty {
            history.record(batch)
            batches = history.batches

            // Files that moved out of the watched folder are no longer pending.
            let movedURLs = Set(batch.operations.map(\.source))
            detectedFiles.removeAll { movedURLs.contains($0.url) }
        }

        lastMessage = Self.summary(moved: batch.operations.count, failures: failures.count)
        lastNotifiedCount = detectedFiles.count
        notifications.clearPending()
        for (move, error) in failures {
            report(
                UserFacingIssue(
                    title: "Couldn't move “\(move.file.filename)”.",
                    suggestion: (error as? OrganizerError).map { organizerAdvice(for: $0) }
                        ?? error.localizedDescription
                ),
                underlying: error
            )
        }

        plan = nil
        planSignature = nil
    }

    func undo(_ batch: OperationBatch) {
        let (restored, failures) = organizer.undo(batch)

        if !restored.isEmpty {
            history.markUndone(batch.id)
            batches = history.batches
            // Restored files are back in the watched folder — pick them up again.
            for operation in restored where operation.source.deletingLastPathComponent() == watchedFolder {
                ingest(url: operation.source)
            }
        }

        if failures.isEmpty {
            lastMessage = "Put \(restored.count) \(restored.count == 1 ? "file" : "files") back."
        } else {
            lastMessage = "Restored \(restored.count); \(failures.count) couldn't be undone."
            for (operation, error) in failures {
                report(
                    UserFacingIssue(
                        title: "Couldn't put “\(operation.filename)” back.",
                        suggestion: (error as? OrganizerError).map { organizerAdvice(for: $0) }
                            ?? error.localizedDescription
                    ),
                    underlying: error
                )
            }
        }
    }

    /// Discards the operation log. Entries can go stale when files are moved
    /// outside Hoot, at which point undo can no longer find them.
    func clearHistory() {
        history.clear()
        batches = history.batches
        lastMessage = "History cleared."
    }

    func undoLast() {
        guard let batch = history.mostRecentUndoable else { return }
        undo(batch)
    }

    /// Turns an organizer error into something actionable.
    func organizerAdvice(for error: OrganizerError) -> String {
        switch error {
        case .sourceMissing:
            return "It was moved or deleted while Hoot was working."
        case .destinationOccupied(let url):
            return "Something else is already at \(url.lastPathComponent)."
        case .escapesWatchedFolder:
            return "That folder is a shortcut leading outside the watched folder, "
                + "so Hoot won't move files into it."
        }
    }

    private static func summary(moved: Int, failures: Int) -> String {
        let movedPart = "Organized \(moved) \(moved == 1 ? "file" : "files")."
        return failures == 0 ? movedPart : "\(movedPart) \(failures) couldn't be moved."
    }
}
