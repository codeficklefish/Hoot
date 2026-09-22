import SwiftUI
import HootKit
import HootPlatformMac

@main
struct HootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    /// The notch HUD. Owned here rather than by the popover, because it
    /// outlives any particular click on the menu bar item.
    @StateObject private var hud = HUDController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState, hud: hud)
        } label: {
            // The menu bar item is rendered from launch, where the popover's
            // contents are not — they wait for a click. Starting from here is
            // what makes Hoot resume watching without being opened first.
            MenuBarLabel(pendingCount: appState.detectedFiles.count)
                .task {
                    // Handed in before `start()`, so the notch has somewhere
                    // to send you from its very first refresh.
                    appState.openReviewWindow = {
                        openWindow(id: WindowID.review)
                        bringWindowForward(titled: "Review")
                    }
                    appState.start()
                    // Brought back here, not in the popover: the HUD should
                    // reappear on login without the menu bar being opened
                    // first, which is the same reason `start()` lives here.
                    hud.restore(appState: appState)

                    // And the welcome, for the same reason again. This hung
                    // off the popover's own `.task`, which does not run until
                    // the popover is built — that is, until somebody has
                    // already found the menu bar icon and clicked it. A
                    // first-time user opened Hoot and saw nothing happen at
                    // all: no Dock icon, by design, and no window either.
                    bringWindowForward(titled: "Welcome to Hoot")
                }
        }
        .menuBarExtraStyle(.window)

        Window("Review", id: WindowID.review) {
            ReviewView(appState: appState)
        }
        .defaultSize(width: 560, height: 480)

        Window("History", id: WindowID.history) {
            HistoryView(appState: appState)
        }
        .defaultSize(width: 560, height: 480)

        Window("Hoot Settings", id: WindowID.settings) {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)

        Window("Welcome to Hoot", id: WindowID.onboarding) {
            OnboardingView(appState: appState)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let review = "review"
    static let history = "history"
    static let settings = "settings"
    static let onboarding = "onboarding"
}

private struct MenuBarLabel: View {
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: HootMark.menuBarIcon)
            if pendingCount > 0 {
                Text("\(pendingCount)")
            }
        }
    }
}
