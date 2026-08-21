import AppKit
import HootKit

/// The Hoot brand mark — a folder outline whose contents read as a pair of
/// owl eyes. Loaded from bundled artwork rather than drawn in code.
enum HootMark {
    /// Icon for the menu bar. The mark is landscape (~1.4:1), so it's kept
    /// shorter than a square icon would be to avoid reading as oversized
    /// next to the system's own menu bar items.
    static let menuBarIcon: NSImage = templateIcon(height: 13)

    /// Larger mark for the popover header.
    static let headerIcon: NSImage = templateIcon(height: 18)

    /// Hero-sized mark for the first-run screen.
    static let onboardingIcon: NSImage = templateIcon(height: 56)

    /// Flagged as a template image so AppKit renders it the same monochrome
    /// way as Wi-Fi, battery, etc. — picking up the right tint automatically
    /// for light/dark appearance and the menu bar's highlighted state.
    static func templateIcon(height: CGFloat) -> NSImage {
        let image = bundled("HootMark-Template")
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: (height * aspect).rounded(), height: height)
        image.isTemplate = true
        return image
    }

    /// Loads artwork from the app bundle first, falling back to SwiftPM's
    /// resource bundle.
    ///
    /// Order matters: in a packaged .app the images live in the conventional
    /// `Contents/Resources`, and `Bundle.module` would look beside the
    /// executable instead — which under the App Sandbox resolves to a path
    /// outside the container and traps. Checking `Bundle.main` first keeps
    /// the shipped app working, while the fallback keeps `swift run` working
    /// during development.
    private static func bundled(_ name: String) -> NSImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            // A missing asset is a build/packaging error, not a runtime
            // condition worth degrading gracefully for.
            fatalError("Missing bundled artwork: \(name).png")
        }
        return image
    }
}
