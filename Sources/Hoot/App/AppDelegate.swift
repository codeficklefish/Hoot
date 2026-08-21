import AppKit
import HootKit

/// Keeps Hoot out of the Dock and Cmd-Tab switcher — it lives in the menu bar only.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
