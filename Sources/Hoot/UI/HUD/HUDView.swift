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
struct HUDView: View {
    let flow: TidyFlow
    /// Open or resting in the housing. Owned by the controller, because the
    /// window has to be resized to match and the keyboard shortcut is only
    /// registered while it is open — neither of which the view can do.
    @Binding var isOpen: Bool
    var notch: NotchShape = .none
    var isWorking: Bool
    var progress: Double

    var onToggleFile: (UUID) -> Void
    var onApply: () -> Void
    var onSkip: () -> Void
    var onToggleRenaming: () -> Void
    var onUndo: () -> Void
    var onDone: () -> Void
    /// Show a different folder without answering this one. Swiping does the
    /// same thing; the controller owns that gesture because it arrives as an
    /// AppKit event rather than a SwiftUI one.
    var onShowGroup: (Int) -> Void = { _ in }

    /// Which of the two tabs is showing. View state rather than app state:
    /// it is where the pointer is looking, not anything about the folder.
    @State private var tab: Tab = .tidy

    private enum Tab: String, CaseIterable, Identifiable {
        case tidy, tray
        var id: String { rawValue }
        var label: String { self == .tidy ? "Tidy" : "Tray" }
        /// `folder` and `tray` — the design's "inbox" under its SF name.
        var symbol: String { self == .tidy ? "folder" : "tray" }
    }

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
        .animation(HUDTokens.resize, value: tab)
        .onHover { hovering in
            if hovering {
                isOpen = true
            } else if !isWorking {
                // A run in progress holds the panel open: files are landing,
                // and the progress of that is the one thing worth staying to
                // watch.
                isOpen = false
            }
        }
    }

    // MARK: - Geometry

    private var isExpanded: Bool {
        switch stage {
        case .idle: return false
        case .finished: return true
        case .reviewing: return isOpen
        }
    }

    private var stage: TidyStage { flow.stage }

    private var width: CGFloat {
        guard isExpanded else { return 190 }
        if case .reviewing = stage, tab == .tray { return HUDTokens.trayWidth }
        return HUDTokens.tidyWidth
    }

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
    //
    // Sits in the top 34pt, which on a notched display is behind the camera.
    // Everything here is either invisible at rest or, once the panel is wider
    // than the cutout, showing either side of it.

    private var housing: some View {
        HStack(spacing: 8) {
            Image(nsImage: HootMark.menuBarIcon)
                .renderingMode(.template)
                .foregroundStyle(HUDTokens.onDark)

            Spacer(minLength: 4)

            Text(flow.pillCount)
                .font(HUDTokens.caption)
                .foregroundStyle(
                    flow.pendingFiles.isEmpty ? HUDTokens.tertiaryText : HUDTokens.onDark
                )
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: HUDTokens.headerHeight)
        // Hidden while the panel is open: the tabs take this line, and on a
        // notched Mac the mark would be behind the camera anyway.
        .opacity(isExpanded ? 0 : 1)
        .accessibilityLabel(flow.pillText)
    }

    // MARK: - What hangs below it

    @ViewBuilder
    private var panel: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                // Only where there is something to put in it. The finished
                // state has neither tabs nor pips, and an empty 20pt row
                // above a one-line receipt is a gap, not a rhythm.
                if case .reviewing = stage {
                    header
                    content.padding(.top, 8)
                } else {
                    content
                }
            }
            .padding(.horizontal, HUDTokens.panelSidePadding)
            .padding(.bottom, HUDTokens.panelBottomPadding)
            .padding(.top, HUDTokens.headerHeight)
            .transition(.opacity)
        }
    }

    /// Tabs on the left, progress on the right — the two things that are true
    /// of the whole walk rather than of the folder currently in front of you.
    private var header: some View {
        HStack(spacing: 4) {
            if case .reviewing = stage {
                ForEach(Tab.allCases) { candidate in
                    NotchTab(
                        symbol: candidate.symbol,
                        label: candidate.label,
                        isSelected: tab == candidate
                    ) {
                        withAnimation(HUDTokens.resize) { tab = candidate }
                    }
                }
            }

            Spacer(minLength: 8)

            if case .reviewing(let step) = stage {
                HStack(spacing: 8) {
                    NotchPips(
                        index: step.index,
                        total: step.total,
                        answered: step.answered,
                        onSelect: onShowGroup
                    )
                    Text(step.stepLabel)
                        .font(HUDTokens.caption2)
                        .foregroundStyle(HUDTokens.tertiaryText)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
        }
        .frame(minHeight: 20)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            EmptyView()

        case .reviewing(let step):
            switch tab {
            case .tidy:
                TidyPanel(
                    step: step,
                    isWorking: isWorking,
                    progress: progress,
                    onToggleFile: onToggleFile,
                    onApply: onApply,
                    onSkip: onSkip,
                    onToggleRenaming: onToggleRenaming
                )
            case .tray:
                TrayPanel(
                    title: flow.waitingTitle,
                    detail: flow.waitingDetail(),
                    files: flow.pendingFiles,
                    captions: flow.trayCaptions(),
                    onSortAll: { withAnimation(HUDTokens.resize) { tab = .tidy } }
                )
            }

        case .finished(let summary):
            FinishedRow(summary: summary, onUndo: onUndo, onDone: onDone)
        }
    }
}

// MARK: - Done

/// The receipt: what moved, what was renamed, and that it can all be taken
/// back.
///
/// Undo is the design's one action here. Done is not in the artboard and is
/// here anyway: a web page can leave a receipt on screen forever, an app has
/// to be told the walk is over so the next pile can start.
private struct FinishedRow: View {
    let summary: TidySummary
    let onUndo: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(HUDTokens.confident)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(HUDTokens.bodyMedium)
                    .foregroundStyle(HUDTokens.onDark)
                    .monospacedDigit()
                Text(summary.detail)
                    .font(HUDTokens.caption2)
                    .foregroundStyle(HUDTokens.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NotchAction(
                symbol: "clock.arrow.circlepath",
                label: "Undo",
                help: "Put every file this walk moved back where it was",
                action: onUndo
            )
            NotchAction(
                symbol: "checkmark",
                label: "Done",
                tone: .ghost,
                help: "Close the HUD until the next pile",
                action: onDone
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
