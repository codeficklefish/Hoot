import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// What Hoot remembers about how this person files things.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    func forgetFolderPreference(proposed: String) {
        folderPreferences.forget(proposed: proposed)
        folderPreferences.save()
    }

    /// Rebuilds the personal model from the watched folder's own subfolders.
    ///
    /// Nothing is asked of the user: a file already sitting in "Finance" is a
    /// labelled example of what they mean by finance. Reports measured
    /// accuracy rather than assuming the model is worth using.
    func relearnFromFolders() async {
        guard let root = watchedFolder else { return }

        // Folders show where files ended up; corrections show where Hoot was
        // wrong. Both are training data, the latter weighted more heavily.
        let samples = TrainingCorpus.gather(from: root) + corrections.trainingSamples
        guard samples.count >= LearnedClassifier.minimumCorpusSize else {
            learned = nil
            learnedAccuracy = nil
            lastMessage = "Not enough sorted files yet — Hoot needs about "
                + "\(LearnedClassifier.minimumCorpusSize) across a few folders."
            return
        }

        let model = LearnedClassifier.train(on: samples)
        let (accuracy, answered, total) = LearnedClassifier.crossValidate(samples)

        model.save()
        learned = model.isUsable ? model : nil
        learnedAccuracy = answered > 0 ? accuracy : nil
        lastMessage = "Learned from \(total) files — right \(Int(accuracy * 100))% of the time "
            + "on the \(Int(Double(answered) / Double(total) * 100))% it recognizes."
    }

    func forgetLearnedFolders() {
        learned = nil
        learnedAccuracy = nil
        LearnedClassifier().save()
        lastMessage = "Forgot what Hoot learned from your folders."
    }

    func clearFolderPreferences() {
        folderPreferences.removeAll()
        folderPreferences.save()
        lastMessage = "Forgot your saved folder names."
    }

    func clearCorrections() {
        corrections.removeAll()
        corrections.save()
        lastMessage = "Forgot your past corrections."
    }
}
