import Foundation

/// The shape of a display's top edge, as far as the HUD is concerned.
///
/// The notch is a *hole* in the panel, not a dark rectangle: nothing drawn
/// inside it reaches a pixel. So the HUD covers that region deliberately —
/// its black runs to the very top of the screen and is simply invisible
/// where the camera housing is, which is what makes the visible part below
/// read as the same object rather than a window parked underneath one.
public struct NotchShape: Equatable, Sendable {
    /// Height of the cutout. Zero on a display without one.
    public let height: Double
    /// Width of the cutout, measured between the two strips of menu bar the
    /// system leaves usable on either side of it.
    public let width: Double
    /// Centre of the cutout — which is **not** the centre of the screen. On
    /// a 1710pt display the midpoint is 855 and the notch is centred on
    /// 855.5; aligning to the screen instead of the camera left a one-point
    /// seam down one side of the housing it is meant to continue.
    public let centerX: Double

    public init(height: Double, width: Double, centerX: Double) {
        self.height = height
        self.width = width
        self.centerX = centerX
    }

    public static let none = NotchShape(height: 0, width: 0, centerX: 0)

    public var hasNotch: Bool { height > 0 }
}

/// Where the HUD's panel goes.
///
/// Pure arithmetic, and in the engine rather than the app target on purpose.
/// The previous attempt at this surface put its geometry in a SwiftUI view,
/// where the verification suite could not reach it — and a one-point seam
/// against the bezel then went unnoticed until someone looked at the screen.
/// Numbers that can be checked should be checked.
public enum HUDPlacement {

    /// Half a point of overlap each side, so rounding can never leave a
    /// hairline of desktop between the HUD and the bezel. It hides behind
    /// the housing, which is the one place a couple of stray points cost
    /// nothing.
    public static let bleed: Double = 2

    /// The narrowest the panel may be: at least as wide as the cutout, or
    /// the shape would pinch in at the very point it is meant to continue
    /// from.
    public static func minimumWidth(for notch: NotchShape) -> Double {
        guard notch.hasNotch else { return 0 }
        return notch.width + bleed
    }

    /// The panel's whole frame, in screen coordinates.
    ///
    /// Returns the width as well as the origin deliberately. Centring for
    /// one width and then sizing the window to another leaves the HUD a few
    /// points off the cutout — which is the exact class of bug that took
    /// four sessions to see the first time, because half a point of seam
    /// against a black bezel is invisible until you look for it.
    ///
    /// - Parameter screenTopY: the top edge of the display — `frame.maxY`,
    ///   not `visibleFrame.maxY`. The HUD covers the menu bar rather than
    ///   hanging below it, which is the difference between the notch looking
    ///   taller and a window looking parked.
    public static func frame(
        contentWidth: Double,
        contentHeight: Double,
        notch: NotchShape,
        screenTopY: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let width = max(contentWidth, minimumWidth(for: notch))
        return (
            x: notch.centerX - width / 2,
            y: screenTopY - contentHeight,
            width: width,
            height: contentHeight
        )
    }

    /// How far the panel's top edge sits below the top of the display.
    /// Zero is the only correct answer on a notched screen, and the reason
    /// this is a function rather than a comment.
    public static func gapAboveTop(
        originY: Double,
        contentHeight: Double,
        screenTopY: Double
    ) -> Double {
        screenTopY - (originY + contentHeight)
    }
}
