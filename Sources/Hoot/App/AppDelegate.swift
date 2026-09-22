import AppKit
import HootKit

/// Keeps Hoot out of the Dock and Cmd-Tab switcher — it lives in the menu bar only.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Shows a window this app has just asked SwiftUI to open.
///
/// `openWindow` builds the scene's window, and that is all it does.
/// `NSApp.activate` is a *request* to come forward, which the system may
/// decline — and it declines for an accessory app the person has never
/// brought to the front, which is every first launch. The window then exists
/// and is never mapped: a new user opened Hoot, got no Dock icon by design and
/// no welcome either, and had to find the menu bar icon unaided.
///
/// `orderFrontRegardless` is the one that does not ask. The activate call
/// stays because it is what gives the window keyboard focus when it is
/// granted; the ordering no longer depends on it being granted.
@MainActor
func bringWindowForward(titled title: String) {
    NSApp.activate(ignoringOtherApps: true)
    // The scene's window does not exist yet at the moment `openWindow`
    // returns — it is built on the next turn of the run loop.
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.title == title }) else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
