import SwiftUI

/// The controls the notch HUD is built from, as the design system draws them.
///
/// Round rather than rectangular, captioned rather than labelled inside, and
/// sized in points the panel can afford: a 560pt panel hanging off a camera
/// housing has room for three decisions and no room for three sentences. The
/// caption under each one carries the words the button cannot.

/// A round icon button with its name underneath.
struct NotchAction: View {
    enum Tone {
        /// The safe answer, and the only colour on the panel.
        case confident
        /// Everything else that does something.
        case standard
        /// A control that is currently off — present, legible, not shouting.
        case ghost
    }

    let symbol: String
    let label: String
    var tone: Tone = .standard
    var isEnabled = true
    /// The long form of what this does, for the tooltip. The caption is two
    /// words; this is the sentence with the count in it.
    var help: String?
    let action: () -> Void

    private static let diameter: CGFloat = HUDTokens.actionDiameter

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: HUDTokens.captionGap) {
                ZStack {
                    Circle().fill(fill)
                    Image(systemName: symbol)
                        // 42% of the button, which is the design's ratio and
                        // the reason the circle reads at a glance.
                        .font(.system(size: (Self.diameter * 0.42).rounded(), weight: .medium))
                        .foregroundStyle(foreground)
                }
                .frame(width: Self.diameter, height: Self.diameter)

                Text(label)
                    .font(HUDTokens.caption2)
                    .foregroundStyle(HUDTokens.secondaryText)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help ?? label)
        .onHover { hovering in
            withAnimation(HUDTokens.fade) { isHovered = hovering && isEnabled }
        }
    }

    private var fill: Color {
        switch tone {
        case .confident: return HUDTokens.confident
        case .standard: return isHovered ? HUDTokens.tileHover : HUDTokens.tile
        case .ghost: return .clear
        }
    }

    private var foreground: Color {
        switch tone {
        case .confident: return HUDTokens.onConfident
        case .standard: return HUDTokens.onDark
        case .ghost: return HUDTokens.secondaryText
        }
    }
}

/// A file as a square tile: the tray's unit.
///
/// A tile rather than a row because the tray answers "how much is waiting",
/// not "what exactly is waiting" — six tiles read as a quantity at a glance
/// where six filenames would have to be read one at a time.
struct NotchFileTile: View {
    let symbol: String
    let name: String
    let caption: String?

    private static let side: CGFloat = HUDTokens.tileSide

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: HUDTokens.radiusTile, style: .continuous)
                .fill(HUDTokens.tile)
                .overlay {
                    RoundedRectangle(cornerRadius: HUDTokens.radiusTile, style: .continuous)
                        .strokeBorder(HUDTokens.hairline, lineWidth: 1)
                }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: (Self.side * 0.36).rounded()))
                        .foregroundStyle(HUDTokens.secondaryText)
                }
                .frame(width: Self.side, height: Self.side)

            if let caption {
                Text(caption)
                    .font(HUDTokens.caption2)
                    .foregroundStyle(HUDTokens.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.side)
        .help(name)
    }
}

/// The count of everything that did not fit as a tile.
struct NotchMoreTile: View {
    let count: Int

    var body: some View {
        RoundedRectangle(cornerRadius: HUDTokens.radiusTile, style: .continuous)
            .fill(HUDTokens.tile)
            .overlay {
                RoundedRectangle(cornerRadius: HUDTokens.radiusTile, style: .continuous)
                    .strokeBorder(HUDTokens.hairline, lineWidth: 1)
            }
            .overlay {
                Text("+\(count)")
                    .font(HUDTokens.caption)
                    .foregroundStyle(HUDTokens.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: HUDTokens.tileSide, height: HUDTokens.tileSide)
    }
}

/// One of the HUD's two tabs.
struct NotchTab: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? HUDTokens.onDark : HUDTokens.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: HUDTokens.tabHeight)
            .background(
                isSelected ? AnyShapeStyle(HUDTokens.tileHover) : AnyShapeStyle(Color.clear),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// How far through the folders this walk is — and the way to move through it.
///
/// Pips rather than a sentence: the shape of the remaining work is the useful
/// part, and it fits beside the tabs where "3 of 7 folders" would not. The
/// sentence is there too, next to them, for the one thing pips cannot say —
/// exactly how many are left.
///
/// Each one is also a target. A pip is 6pt of ink, so the thing you click is
/// the 20pt of nothing around it: the dot says where you are, the padding is
/// what makes it somewhere you can go.
struct NotchPips: View {
    let index: Int
    let total: Int
    /// Folders already filed or left. They keep their place in the row so the
    /// walk does not appear to shrink as it is answered, but they are no
    /// longer anywhere to go back to.
    var answered: Set<Int> = []
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 0), id: \.self) { position in
                Button {
                    onSelect?(position)
                } label: {
                    Capsule()
                        .fill(colour(at: position))
                        .frame(width: position == index ? 16 : 6, height: 6)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil || answered.contains(position) || position == index)
                .help(helpText(at: position))
            }
        }
        .animation(HUDTokens.resize, value: index)
    }

    private func colour(at position: Int) -> Color {
        if answered.contains(position) { return HUDTokens.secondaryText }
        if position == index { return HUDTokens.onDark }
        return HUDTokens.tileHover
    }

    private func helpText(at position: Int) -> String {
        if answered.contains(position) { return "Folder \(position + 1), already answered" }
        if position == index { return "Folder \(position + 1), showing now" }
        return "Show folder \(position + 1)"
    }
}
