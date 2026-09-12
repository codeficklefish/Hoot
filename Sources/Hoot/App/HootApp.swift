import SwiftUI
import HootKit
import HootPlatformMac

@main
struct HootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    /// Lives as long as the app: the island is an ambient surface, not
    /// something a window owns.
    @State private var island: IslandController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
                .task {
                    // The island is AppKit and cannot reach SwiftUI's
                    // environment, so it is handed the one thing it needs from
                    // here rather than opening windows its own way.
                    appState.presentWindow = { openWindow(id: $0) }
                    if island == nil { island = IslandController(appState: appState) }

                    // First launch: introduce the app before it's handed a
                    // folder, rather than showing an empty popover.
                    guard appState.needsOnboarding else { return }
                    openWindow(id: WindowID.onboarding)
                    NSApp.activate(ignoringOtherApps: true)
                }
        } label: {
            MenuBarLabel(pendingCount: appState.detectedFiles.count)
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
