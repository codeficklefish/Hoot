import SwiftUI

/// The Hoot design system, as far as the HUD uses it.
///
/// Named here rather than inlined so the panel reads as a design rather than
/// a pile of numbers, and so a token that changes upstream changes in one
/// place. Values come from the design system's token files — `colors.css`,
/// `semantic.css`, `typography.css`, `spacing.css`, `radius.css`,
/// `motion.css` — and specifically from the notch block of `semantic.css`,
/// which is the one dark register in the system.
///
/// The surface is true black rather than the app icon's charcoal. That is the
/// design's decision and it is load-bearing: the HUD reads as a continuation
/// of the bezel, and anything lighter than the glass reads as a dark-mode
/// window parked at the top of the screen instead. It never follows the
/// system appearance for the same reason.
enum HUDTokens {

    // MARK: - Colour

    /// `--notch-surface`. Not a dark grey: the bezel is black.
    static let ground = Color.black
    /// `--notch-ink-1`.
    static let onDark = Color.white
    /// `--notch-ink-2`, for labels under a control and secondary text.
    static let secondaryText = Color.white.opacity(0.62)
    /// `--notch-ink-3`, for the reason line, captions and struck-out names.
    static let tertiaryText = Color.white.opacity(0.38)

    /// `--notch-tile`, the fill under a round action or a file tile.
    static let tile = Color.white.opacity(0.07)
    /// `--notch-tile-hover`, and the unreached pip.
    static let tileHover = Color.white.opacity(0.12)
    /// `--notch-hairline`.
    static let hairline = Color.white.opacity(0.10)

    /// `--status-confident`. The one colour in the HUD, and it means the same
    /// thing here as everywhere else in the app: this is the safe answer.
    static let confident = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    /// What sits on top of it — near-black rather than white, as the design
    /// has it, because green this bright cannot carry white text.
    static let onConfident = Color(red: 0x06 / 255, green: 0x2C / 255, blue: 0x12 / 255)
    /// `--orange-500`, the brand accent. Used only where the design does.
    static let accent = Color(red: 0xFF / 255, green: 0x8C / 255, blue: 0x14 / 255)
    /// `--ink-1`, for text on a light control.
    static let ink = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)

    static let cardFill = tile
    static let cardStroke = hairline
    static let controlStroke = hairline
    static let controlFill = tile
    static let chipFill = tileHover

    // MARK: - Type
    //
    // The app's own macOS text styles, given as explicit sizes because the
    // HUD is not a standard control and must not resize with Dynamic Type —
    // it has to stay the width of a camera housing.

    // Each role sits one rung up the app's own scale from the artboard's.
    // The design was drawn at the size a browser shows a Mac at; on the
    // glass, 10pt captions under a camera housing are a squint, and the
    // panel has the room.

    static let headline = Font.system(size: 15, weight: .semibold)
    /// `--text-app-title`, the group name and the tray's title.
    static let bodyMedium = Font.system(size: 15, weight: .medium)
    /// `--text-app-callout`, file names and tab labels.
    static let caption = Font.system(size: 13)
    /// `--text-app-caption`, every label under a control.
    static let caption2 = Font.system(size: 11)
    /// --text-app-caption2. The size and age columns, which sit beside a
    /// filename and must not compete with it.
    static let caption3 = Font.system(size: 10)
    /// The struck-out name. Monospaced so the thing being replaced reads as
    /// machine output next to the name that replaces it.
    static let mono = Font.system(size: 11, design: .monospaced)

    // MARK: - Space and shape

    static let radiusControl: CGFloat = 7    // --radius-md
    static let radiusRow: CGFloat = 5        // --radius-sm
    /// `--notch-radius-inner`, for file tiles.
    /// `--notch-radius`. The panel's bottom corners.
    static let radiusPanel: CGFloat = 26
    /// `--radius-xl`. The collapsed bar's, which is a smaller shape and needs
    /// a tighter curve to keep the same weight of corner.
    static let radiusBar: CGFloat = 14

    /// Height of the collapsed bar, and of the header in every other state.
    /// Matches a camera housing, which is the point: at rest the HUD is the
    /// same shape as the notch and therefore invisible on it.
    /// The menu bar row, measured: `frame.maxY - visibleFrame.maxY` is 34 on
    /// a notched display, where the cutout itself is 33. The bar covers the
    /// row rather than the cutout, so it ends where the menu bar ends — tying
    /// it to the notch instead left a one-point seam of menu bar showing.
    static let headerHeight: CGFloat = 34

    /// Each file row in the expanded panel, used to size the panel before it
    /// is laid out — the window has to be told how big to be.

    /// The round actions, and the file tiles in the tray.
    static let actionDiameter: CGFloat = 38
    /// The tab pills.
    static let tabHeight: CGFloat = 24

    /// `--space-4`, the gap between a control and its caption.
    static let captionGap: CGFloat = 4

    /// The panel's own padding: tight at the top where it meets the housing,
    /// wider at the bottom where it meets nothing.
    static let panelTopPadding: CGFloat = 10
    static let panelSidePadding: CGFloat = 16
    static let panelBottomPadding: CGFloat = 18

    /// Panel widths. Two, because the two tabs are different shapes of
    /// answer: Tidy carries a folder's worth of rows, the Tray carries a row
    /// of tiles, and one width flattering both would flatter neither.
    /// The panel, open. A vertical list wants a reading measure rather than
    /// the width two columns of filenames needed.
    static let shelfWidth: CGFloat = 420
    /// One file. Icon, name and two numbers on a single line.
    static let shelfRowHeight: CGFloat = 26
    /// The footer's pill controls.
    static let pillHeight: CGFloat = 20

    /// How far the resting bar reaches past the camera housing on each side.
    ///
    /// The bar used to be exactly the width of the cutout, which made it
    /// invisible — and made everything drawn on it invisible too, since the
    /// housing was directly over the mark and the folder's name. Reaching
    /// past the cutout is what lets the bar say which folder it is showing
    /// without being opened.
    static let restingShoulder: CGFloat = 88

    /// How far the mark and the folder's name stand off the camera housing.
    /// Close enough to read as one object continuing out of the hardware,
    /// far enough not to touch the bezel.
    static let housingGap: CGFloat = 10

    // MARK: - Motion

    /// `--dur-base` with `--ease-standard`. The design states this curve
    /// outright, so it is used outright rather than approximated with a
    /// spring: it is the same motion the shell uses for width and height.
    static let resize = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
    /// `--dur-fast` with the same curve, for tints and opacity.
    static let fade = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.14)
}
