import AppKit

/// A panel allowed to reach the top of the screen.
///
/// AppKit constrains window frames so they cannot cover the menu bar. That
/// is right for windows and wrong for this one: the HUD's whole premise is
/// that it continues out of the camera housing, and a frame stopped 34pt
/// short of the display's top edge leaves it floating under the notch
/// instead.
final class HUDPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Borderless panels refuse key status, and this one has to be able to
    /// accept it — not while it is merely being pointed at, but once somebody
    /// has clicked a row in it.
    ///
    /// The spacebar is why. A key this window cannot receive is a key that
    /// goes to whatever *is* frontmost, so previewing with space without
    /// being key would put a space in the middle of someone's sentence and
    /// preview the file as well. A global hot key is worse still: it would
    /// take the spacebar away from every app on the Mac.
    override var canBecomeKey: Bool { true }

    /// Non-activating on purpose: pointing at the HUD must never pull focus
    /// out of whatever the person is actually doing, which is the difference
    /// between an ambient indicator and an interruption.
    static func make() -> HUDPanel {
        let panel = HUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // the HUD draws its own
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Visible on every space and over full-screen apps: a folder fills
        // up while you are working, which is usually somewhere else.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}
