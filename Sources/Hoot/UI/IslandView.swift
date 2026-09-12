import SwiftUI
import HootKit

/// What the top of a display looks like, so the island can meet it rather
/// than float below it.
///
/// The notch is a hole in the panel, not a dark rectangle: nothing drawn
/// inside it reaches a pixel. So the island covers that region deliberately —
/// its black runs to the very top of the screen and is simply invisible where
/// the camera housing is, which is what makes the visible part below read as
/// the same object rather than a window parked underneath one.
struct NotchMetrics: Equatable {
    /// Height of the cutout. Zero on a display without one.
    let height: CGFloat
    /// Width of the cutout, measured between the two strips of menu bar the
    /// system leaves usable on either side of it.
    let width: CGFloat
    /// Centre of the cutout in screen coordinates — which is not the centre
    /// of the screen. On a 1710pt display the midpoint is 855, and the notch
    /// is centred on 855.5; aligning to the screen instead of the camera left
    /// the island a point to the left of the housing it is meant to continue.
    let centerX: CGFloat

    static let none = NotchMetrics(height: 0, width: 0, centerX: 0)

    var hasNotch: Bool { height > 0 }

    /// Half a point of overlap each side, so rounding can never leave a
    /// hairline of desktop between the island and the bezel. It hides behind
    /// the housing, which is the one place a couple of stray points cost
    /// nothing.
    static let bleed: CGFloat = 2
}

/// One destination folder in the island's preview.
struct IslandGroup: Equatable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

/// The island's two states.
///
/// Collapsed is a glance: how many files are waiting, nothing more. Expanded
/// is the decision — what Hoot is about to do, how it decided, and the one
/// action worth taking. Anything beyond that belongs in the review window,
/// which is a page, not a pill.
enum IslandState: Equatable {
    /// Files have arrived and settled.
    case waiting(count: Int, groups: [IslandGroup])
    /// A batch just moved, and can still be taken back.
    case organized(message: String, canUndo: Bool)

    var isWaiting: Bool { if case .waiting = self { return true }; return false }
}

/// A capsule that sits under the notch and opens into a panel when you point
/// at it.
///
/// Black regardless of appearance, which is the one thing the real Dynamic
/// Island never changes: it reads as a continuation of the hardware rather
/// than a window, and that only holds if it stays the colour of the bezel.
///
/// The expanded state puts the outcome beside the choice — the folders that
/// are about to appear on the left, the way of deciding them on the right —
/// so switching between sorting by meaning and by type is answered by looking
/// rather than by trying it and undoing.
struct IslandView: View {
    let state: IslandState
    let mode: SortingMode
    var notch: NotchMetrics = .none
    var onSelectMode: (SortingMode) -> Void
    var onReview: () -> Void
    var onUndo: () -> Void
    var onDismiss: () -> Void

    @State private var isExpanded = false

    /// Collapsing on exit rather than on a timer: a pointer leaving is the
    /// clearest "I am done with this" a pill can be given.
    private var expanded: Bool { isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 0) {
            header

            if expanded {
                if case .waiting(_, let groups) = state {
                    HStack(alignment: .top, spacing: 10) {
                        FolderPreview(groups: groups, mode: mode)
                        ModeList(selected: mode, onSelect: onSelectMode)
                    }
                }

                HStack(spacing: 6) {
                    switch state {
                    case .waiting:
                        IslandButton("Review", prominent: true, action: onReview)
                        IslandButton("Later", action: onDismiss)
                    case .organized(_, let canUndo):
                        if canUndo { IslandButton("Undo", prominent: true, action: onUndo) }
                        IslandButton("Done", action: onDismiss)
                    }
                }
            }
        }
        .padding(.horizontal, expanded ? 16 : 14)
        .padding(.bottom, expanded ? 14 : 8)
        // Nothing drawn behind the camera housing is visible, so the content
        // starts below it. Without this the collapsed island would lose its
        // first line to a piece of aluminium.
        .padding(.top, (expanded ? 14 : 8) + notch.height)
        // At least as wide as the cutout, or the shape would pinch in at the
        // very point it is meant to continue from.
        .frame(minWidth: notch.hasNotch ? notch.width + NotchMetrics.bleed : 0)
        .background(.black, in: shape)
        // No shadow along the top edge on a notched display: there is nothing
        // above it to cast onto, and the blur would show as a grey seam
        // against the bezel.
        .shadow(color: .black.opacity(notch.hasNotch ? 0.28 : 0.35), radius: 16, y: notch.hasNotch ? 10 : 8)
        .fixedSize()
        .onHover { hovering in
            // The spring is the whole point: the island is recognisable by how
            // it moves, not by being a rounded rectangle.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                isExpanded = hovering
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: HootMark.menuBarIcon)
                .renderingMode(.template)
                .foregroundStyle(.white)

            Text(headline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !expanded, case .waiting(let count, _) = state {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.white, in: Capsule())
            }
        }
    }

    /// Square at the top when it meets the notch, because a rounded corner
    /// there would open a sliver of desktop between the island and the bezel
    /// and give the join away.
    private var shape: UnevenRoundedRectangle {
        let radius: CGFloat = expanded ? 26 : 18
        return UnevenRoundedRectangle(
            topLeadingRadius: notch.hasNotch ? 0 : radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: notch.hasNotch ? 0 : radius,
            style: .continuous
        )
    }

    private var headline: String {
        switch state {
        case .waiting(let count, _):
            return expanded ? "\(count) \(count == 1 ? "file is" : "files are") waiting" : "Hoot"
        case .organized(let message, _):
            return message
        }
    }
}

// MARK: - Preview of the outcome

/// What the folder will look like afterwards, named and counted.
///
/// This is the half of the panel that makes the choice next to it meaningful:
/// "By type" is an abstraction until you see it produce Screenshots 14,
/// Images 6, Installers 2.
private struct FolderPreview: View {
    let groups: [IslandGroup]
    let mode: SortingMode

    /// Five rows is what fits beside the mode list without the panel growing
    /// taller than the choice it exists to support.
    private static let visibleRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(groups.prefix(Self.visibleRows)) { group in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(group.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(group.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if groups.count > Self.visibleRows {
                Text("+\(groups.count - Self.visibleRows) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if groups.isEmpty {
                Text(mode == .byType ? "Nothing recognized yet." : "Working out what these are…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 168, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - The choice

/// The sorting modes, as a list you point at.
private struct ModeList: View {
    let selected: SortingMode
    let onSelect: (SortingMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SortingMode.allCases) { mode in
                ModeRow(mode: mode, isSelected: mode == selected) { onSelect(mode) }
            }

            // The consequence of the choice, not a description of it. This is
            // the sentence someone actually decides on — that one mode reads
            // files and the other never opens one — so it belongs on screen
            // rather than in a tooltip nobody waits for.
            Text(selected.tradeoff)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.top, 4)
        }
        .frame(width: 186, alignment: .leading)
    }
}

private struct ModeRow: View {
    let mode: SortingMode
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    /// Each mode gets a colour of its own, so the row is identifiable before
    /// the label is read — the same reason the menu bar mark is a shape and
    /// not the word "Hoot".
    private var tint: Color {
        switch mode {
        case .byMeaning: return Color(red: 1.0, green: 0.55, blue: 0.08)
        case .byType: return Color(red: 0.36, green: 0.62, blue: 0.98)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                Text(mode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.14 : (isSelected ? 0.08 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(mode.tradeoff)
    }
}

private struct IslandButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
