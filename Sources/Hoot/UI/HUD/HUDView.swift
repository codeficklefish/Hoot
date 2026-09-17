import SwiftUI
import HootKit

/// The HUD: a bar the shape of the camera housing that opens into a panel.
///
/// At rest it is exactly the size of the notch — 190 wide against a cutout of
/// 185 — so on the hardware it is meant for, it is *invisible*. Pointing at
/// it opens the panel, and taking the pointer away closes it again. That is
/// the design's own gesture, and it is the one that suits a surface with no
/// title bar and nothing to click at rest: there is no affordance to aim at,
/// so aiming at the housing has to be enough.
///
/// Black in both appearances, which is the one thing the real Dynamic Island
/// never changes. It reads as a continuation of the hardware rather than a
/// window, and that only holds if it stays the colour of the bezel.
///
/// What it shows is a *shelf* — the folders you chose, listed. It used to
/// walk the plan one folder at a time, which was the review window's job
/// done again in a smaller space. Deciding where files go stayed there; this
/// answers the other question, which is simply what is in the folder.
struct HUDView: View {
    let shelf: FileShelf
    /// Open or resting in the housing. Owned by the controller, because the
    /// window has to be resized to match and the keyboard shortcut is only
    /// registered while it is open — neither of which the view can do.
    @Binding var isOpen: Bool
    var notch: NotchShape = .none
    /// Something is going on that the pointer leaving must not interrupt —
    /// a drag out of the panel, most of all, which begins by leaving it.
    var isHoldingOpen: Bool = false
    /// How many files in this folder the plan would move. Zero everywhere
    /// but the watched folder, because that is the only one with a plan.
    var untidy: Int = 0
    /// Passed in rather than read, so every relative time on screen is
    /// measured from one instant and the suite can pin it.
    var now: Date = Date()

    var onShowFolder: (Int) -> Void = { _ in }
    var onSelect: (String) -> Void = { _ in }
    var onCycleSort: () -> Void = {}
    var onReveal: () -> Void = {}
    var onTidy: () -> Void = {}
    var onPreview: (URL) -> Void = { _ in }
    var onDragStart: () -> Void = {}
    var onRevealEntry: (URL) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .top) {
            housing
            panel
        }
        .frame(width: width, alignment: .top)
        .background(HUDTokens.ground, in: shape)
        // A deep drop for lift, and a hairline ring so the edge reads against
        // a light desktop.
        .shadow(color: .black.opacity(0.40), radius: 30, y: 26)
        .overlay(shape.stroke(Color.black.opacity(0.55), lineWidth: 0.5))
        .animation(HUDTokens.resize, value: isExpanded)
        .onHover { hovering in
            if hovering {
                isOpen = true
            } else if !isHoldingOpen {
                isOpen = false
            }
        }
    }

    // MARK: - Geometry

    /// No longer a question about whether there is anything to file.
    ///
    /// It used to be: the panel only existed while a walk was in progress,
    /// so on a tidy folder there was nothing at the notch to point at and
    /// hovering did nothing at all. A shelf is worth opening whenever it is
    /// switched on.
    private var isExpanded: Bool { isOpen || isHoldingOpen }

    private var width: CGFloat { isExpanded ? HUDTokens.shelfWidth : 190 }

    /// Square at the top, because a rounded corner there would open a sliver
    /// of desktop between the HUD and the bezel and give the join away.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: isExpanded ? HUDTokens.radiusPanel : HUDTokens.radiusBar,
            bottomTrailingRadius: isExpanded ? HUDTokens.radiusPanel : HUDTokens.radiusBar,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - The bar over the housing

    /// The mark, and the name of the folder being shown.
    ///
    /// A name rather than a count. A number here would be a third one beside
    /// the popover's chips and the review window's header, and those two
    /// disagreeing once was the bug that made all three read one plan.
    private var housing: some View {
        HStack(spacing: 8) {
            Image(nsImage: HootMark.menuBarIcon)
                .renderingMode(.template)
                .foregroundStyle(HUDTokens.onDark)

            Spacer(minLength: 4)

            Text(shelf.pillText)
                .font(HUDTokens.caption2)
                .foregroundStyle(HUDTokens.onDark)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: HUDTokens.headerHeight)
        // Hidden while the panel is open: the tabs take this line, and on a
        // notched Mac the mark would be behind the camera anyway.
        .opacity(isExpanded ? 0 : 1)
        .accessibilityLabel("Hoot — \(shelf.pillText)")
    }

    // MARK: - What hangs below it

    @ViewBuilder
    private var panel: some View {
        if isExpanded {
            ShelfPanel(
                shelf: shelf,
                untidy: untidy,
                now: now,
                onShowFolder: onShowFolder,
                onSelect: onSelect,
                onCycleSort: onCycleSort,
                onReveal: onReveal,
                onTidy: onTidy,
                onPreview: onPreview,
                onDragStart: onDragStart,
                onRevealEntry: onRevealEntry
            )
            .padding(.horizontal, HUDTokens.panelSidePadding)
            .padding(.bottom, HUDTokens.panelBottomPadding)
            .padding(.top, HUDTokens.headerHeight)
            .transition(.opacity)
        }
    }
}
