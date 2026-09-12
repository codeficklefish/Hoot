import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// Telling the user what happened, or could not.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    /// The one issue Hoot raises and withdraws on its own, rather than
    /// leaving for the user to dismiss. Kept in one place so the branch that
    /// clears it cannot drift from the branch that raises it.
    static let smartSortingOffTitle = "Smart sorting is off."

    /// Reports whether the configured provider can actually run, so Settings
    /// can say "on-device model still downloading" instead of failing silently.
    func refreshProviderStatus() async {
        // Sorting by type is a decision not to use a model, so a banner
        // announcing that no model is running would be reporting the setting
        // back to the person who chose it.
        guard sortingMode.usesModel else {
            providerStatus = "Sorting by type — no model is used."
            clearIssue(titled: Self.smartSortingOffTitle)
            return
        }

        guard let provider = MacPlatform.makeAIProvider(for: settings) else {
            providerStatus = "Using filename rules only."
            clearIssue(titled: Self.smartSortingOffTitle)
            return
        }
        switch await provider.availability() {
        case .available:
            providerStatus = "\(provider.displayName) is ready."
            // The warning below outlives whatever caused it: turning Apple
            // Intelligence on in System Settings fixes the model, but the
            // banner would sit there claiming otherwise until the user
            // dismissed it — which reads as the fix not having worked.
            clearIssue(titled: Self.smartSortingOffTitle)
        case .unavailable(let reason):
            providerStatus = "\(reason) Falling back to filename rules."
            report(
                UserFacingIssue(
                    title: Self.smartSortingOffTitle,
                    suggestion: "\(reason) Hoot will sort by filename instead.",
                    severity: .warning
                )
            )
        }
    }

    /// Records a problem for display, and logs it for diagnosis.
    func report(_ issue: UserFacingIssue, underlying: Error? = nil) {
        NSLog("Hoot: \(issue.title)\(underlying.map { " — \($0.localizedDescription)" } ?? "")")
        issues.removeAll { $0.title == issue.title }
        issues.insert(issue, at: 0)
        if issues.count > 5 { issues = Array(issues.prefix(5)) }
    }

    /// Withdraws an issue Hoot raised itself, once the condition behind it
    /// has gone. Matching on title is what `report` already does to replace
    /// a repeated issue, so the two stay consistent.
    func clearIssue(titled title: String) {
        issues.removeAll { $0.title == title }
    }

    func dismissIssue(_ id: UUID) {
        issues.removeAll { $0.id == id }
    }

    func dismissAllIssues() {
        issues.removeAll()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        needsOnboarding = false
    }

    /// Waits for the folder to settle before announcing anything — unzipping
    /// an archive can produce dozens of files in a second, and each one
    /// shouldn't be its own notification.
    func scheduleWaitingNotification() {
        guard announcer.shouldStartQuietPeriod(sweepInProgress: isScanning) else { return }
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: WaitingAnnouncer.quietPeriod)
            guard !Task.isCancelled, let self else { return }
            self.folderSettled()
            await self.announceIfPileGrew()
        }
    }

    /// The folder has stopped changing: a good moment to do the expensive
    /// analysis, so it's finished before Review is ever clicked.
    ///
    /// Kept apart from announcing because it is a different job that happens
    /// to want the same moment — and because it runs whether or not there is
    /// anything worth saying.
    func folderSettled() {
        // Sorting by type has no expensive part, so waking a model for it
        // would be work done purely to be thrown away.
        if sortingMode.usesModel {
            MacPlatform.makeAIProvider(for: settings)?.prewarm()
        }
        precomputePlan()
    }

    func announceIfPileGrew() async {
        guard let announcement = announcer.announcement(
            forPileOf: detectedFiles.count,
            topGroup: summaryByCategory.first?.label
        ) else { return }

        await notifier.notifyFilesWaiting(
            count: announcement.count,
            topGroup: announcement.topGroup
        )
    }
}
