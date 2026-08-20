import Foundation
import UserNotifications

/// Tells the user when files are waiting, without nagging.
///
/// Hoot is a background app, so a notification is the only way it can say
/// "there's something to look at" while the menu bar isn't being watched.
/// Permission is requested lazily — on the first notification worth sending,
/// not at launch — so the prompt arrives with obvious context.
@MainActor
final class NotificationService {
    static let pendingFilesIdentifier = "hoot.pending-files"

    private var hasRequestedAuthorization = false
    private var isAuthorized = false

    /// Notifications need a real bundle; running the bare SwiftPM binary
    /// would trap inside UNUserNotificationCenter.
    private let isBundled = Bundle.main.bundleIdentifier != nil

    /// Announces that files are waiting for review. Replaces any previous
    /// pending-files notification rather than stacking them up.
    func notifyFilesWaiting(count: Int, topGroup: String?) async {
        guard count > 0, await ensureAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(count) \(count == 1 ? "file is" : "files are") waiting"
        content.body = topGroup.map { "Looks like \($0) and more. Click Hoot to review." }
            ?? "Click Hoot in the menu bar to review."
        content.sound = nil // A background tidy-up doesn't warrant a sound.

        let request = UNNotificationRequest(
            identifier: Self.pendingFilesIdentifier,
            content: content,
            trigger: nil
        )

        do {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.pendingFilesIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.pendingFilesIdentifier])
            try await center.add(request)
        } catch {
            NSLog("Hoot: could not post notification: \(error)")
        }
    }

    /// Clears the waiting-files notification once they've been dealt with.
    func clearPending() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.pendingFilesIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.pendingFilesIdentifier])
    }

    private func ensureAuthorized() async -> Bool {
        guard isBundled else { return false }
        if isAuthorized { return true }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
            return true
        case .denied:
            return false
        case .notDetermined:
            // Only ever ask once per launch, so a decline isn't re-prompted.
            guard !hasRequestedAuthorization else { return false }
            hasRequestedAuthorization = true
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .badge])
                return isAuthorized
            } catch {
                NSLog("Hoot: notification permission failed: \(error)")
                return false
            }
        @unknown default:
            return false
        }
    }
}
