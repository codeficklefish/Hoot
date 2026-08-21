import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// The edits a person makes to a plan before agreeing to it.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    func setApproval(_ approved: Bool, forMove moveID: UUID) {
        guard var current = plan else { return }
        for groupIndex in current.groups.indices {
            guard let moveIndex = current.groups[groupIndex].moves.firstIndex(where: { $0.id == moveID })
            else { continue }
            current.groups[groupIndex].moves[moveIndex].isApproved = approved
            plan = current
            return
        }
    }

    /// Renames a group's destination folder, and remembers the correction so
    /// the same suggestion arrives already renamed next time.
    ///
    /// The typed name is sanitized as a path component but otherwise left
    /// alone — unlike model output, the user is allowed to call a folder
    /// whatever they like.
    func renameGroup(_ groupID: UUID, to newName: String) {
        guard var current = plan,
              let groupIndex = current.groups.firstIndex(where: { $0.id == groupID }),
              let safeName = SuggestionValidator.sanitizeUserFolderName(newName)
        else { return }

        let group = current.groups[groupIndex]
        guard safeName != group.name else { return }

        current.groups[groupIndex].name = safeName
        for moveIndex in current.groups[groupIndex].moves.indices {
            current.groups[groupIndex].moves[moveIndex].destinationFolder = safeName
        }
        plan = current

        folderPreferences.remember(proposed: group.proposedName, preferred: safeName)
        folderPreferences.save()
    }

    /// Moves one file into a different group, because the user said so.
    ///
    /// This is the correction that teaches: the choice is recorded and fed
    /// back into the personal model, so files described the same way go to
    /// the right place next time without being asked again.
    func moveFile(_ moveID: UUID, toGroup targetGroupID: UUID) {
        guard var current = plan,
              let targetIndex = current.groups.firstIndex(where: { $0.id == targetGroupID })
        else { return }

        // Find and detach the move from wherever it currently sits.
        var moved: PlannedMove?
        for groupIndex in current.groups.indices {
            guard let moveIndex = current.groups[groupIndex].moves
                .firstIndex(where: { $0.id == moveID }) else { continue }
            guard groupIndex != targetIndex else { return }   // already there
            moved = current.groups[groupIndex].moves.remove(at: moveIndex)
            break
        }
        guard var move = moved else { return }

        let destination = current.groups[targetIndex].name
        let rejected = move.destinationFolder

        move.destinationFolder = destination
        // A role subfolder described the old grouping and rarely survives the
        // move; superseded versions keep theirs, since that is about age.
        if move.roleSubfolder != OrganizationPlanner.demotedSubfolder {
            move.roleSubfolder = nil
        }
        move.isApproved = true
        current.groups[targetIndex].moves.append(move)
        current.groups[targetIndex].moves.sort { $0.file.filename < $1.file.filename }

        // Groups emptied by the move stop being proposed.
        current.groups.removeAll { $0.moves.isEmpty }
        plan = current

        corrections.record(
            features: TrainingCorpus.features(for: move.file),
            chose: destination,
            insteadOf: rejected
        )
        corrections.save()
        lastMessage = "Moved to “\(destination)”. Hoot will remember."
    }

    /// Bulk toggle for the review window's All / None buttons.
    func setApprovalForAll(_ approved: Bool) {
        guard var current = plan else { return }
        for groupIndex in current.groups.indices {
            for moveIndex in current.groups[groupIndex].moves.indices {
                current.groups[groupIndex].moves[moveIndex].isApproved = approved
            }
        }
        plan = current
    }

    func setApproval(_ approved: Bool, forGroup groupID: UUID) {
        guard var current = plan else { return }
        guard let groupIndex = current.groups.firstIndex(where: { $0.id == groupID }) else { return }
        for moveIndex in current.groups[groupIndex].moves.indices {
            current.groups[groupIndex].moves[moveIndex].isApproved = approved
        }
        plan = current
    }
}
