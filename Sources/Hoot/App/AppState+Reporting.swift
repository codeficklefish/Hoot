import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// Telling the user what happened, or could not.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    /// Reports whether the configured provider can actually run, so Settings
    /// can say "on-device model still downloading" instead of failing silently.
    func refreshProviderStatus() async {
        guard let provider = MacPlatform.makeAIProvider(for: settings) else {
            providerStatus = "Using filename rules only."
            return
        }
        switch await provider.availability() {
        case .available:
            providerStatus = "\(provider.displayName) is ready."
        case .unavailable(let reason):
            providerStatus = "\(reason) Falling back to filename rules."
            report(
                UserFacingIssue(
                    title: "Smart sorting is off.",
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
        guard !isScanning else { return } // the initial sweep isn't news
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            await self.notifyIfPileGrew()
        }
    }

    func notifyIfPileGrew() async {
        // The folder has stopped changing: a good moment to do the expensive
        // analysis, so it's finished before Review is ever clicked.
        MacPlatform.makeAIProvider(for: settings)?.prewarm()
        precomputePlan()

        let count = detectedFiles.count
        guard count > lastNotifiedCount else { return }
        lastNotifiedCount = count
        await notifications.notifyFilesWaiting(
            count: count,
            topGroup: summaryByCategory.first?.label
        )
    }
}
