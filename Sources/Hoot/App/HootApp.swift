import SwiftUI
import HootKit
import HootPlatformMac

@main
struct HootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
                .task {
                    // First launch: introduce the app before it's handed a
                    // folder, rather than showing an empty popover.
                    guard appState.needsOnboarding else { return }
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                }
        } label: {
            // The menu bar item is rendered from launch, where the popover's
            // contents are not — they wait for a click. Starting from here is
            // what makes Hoot resume watching without being opened first.
            MenuBarLabel(pendingCount: appState.detectedFiles.count)
                .task { appState.start() }
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
