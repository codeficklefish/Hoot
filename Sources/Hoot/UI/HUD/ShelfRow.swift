import SwiftUI
import HootKit

/// One file, on one line.
///
/// Four columns at fixed widths rather than laid out by priority: the two
/// numbers on the right are the width of the widest thing they will ever
/// hold, so the filename between them does not jump about as the folder is
/// re-sorted. Column widths come from the design, which measured them
/// against "3.9 GB" and "Yest.".
struct ShelfRow: View {
    let row: ShelfRowItem
    let isSelected: Bool
    let age: String
    /// A click. Picking the row and opening it are the same gesture now —
    /// which of the two it turns out to be is decided from how soon it
    /// followed the last one, not by waiting to see. See `ClickPair`.
    let onClick: () -> Void
    /// Hold still to look inside — Quick Look for a file, a list of its
    /// contents for a folder. Never offered for a file that is in the cloud
    /// and not downloaded: opening one would fetch it, and safety rule 5 says
    /// Hoot does not start a download nobody asked for.
    var onPreview: () -> Void = {}
    /// A drag has begun. The panel has to be told, because the first thing a
    /// drag out of it does is take the pointer off it.
    var onDragStart: () -> Void = {}
    var onReveal: () -> Void = {}
    /// Double-click, as in the Finder.
    var onOpen: () -> Void = {}
    /// The disclosure triangle, which is the only control on the row: every
    /// other gesture here acts on the row as a whole.
    var onToggle: () -> Void = {}

    private var entry: ShelfEntry { row.entry }

    private static let glyphWidth: CGFloat = 13
    /// The triangle's column, held even on rows that have no triangle so
    /// every name at a given level starts at the same place.
    private static let twistWidth: CGFloat = 12
    /// One level of nesting. Enough to read as a step in, small enough that
    /// four of them still leave a filename room in a 420pt panel.
    private static let indent: CGFloat = 12
    private static let sizeWidth: CGFloat = 52
    private static let ageWidth: CGFloat = 34

    @State private var isHovered = false

    var body: some View {
        line
            .contentShape(Rectangle())
            // One tap gesture, which fires the moment the click lands.
            //
            // There were two — count 2 declared before count 1, which is how
            // SwiftUI tells them apart. It works, and it costs a quarter of a
            // second: the single tap cannot fire until the double-click
            // interval has passed with no second click, so a row did not look
            // clicked until well after it had been. Making the single tap a
            // `simultaneousGesture` removes the wait and the double-click
            // with it — it wins the arbitration on the first click, and
            // `count: 2` never fires at all.
            //
            // So the pairing moved out of the gesture system entirely, into
            // `ClickPair`, which decides from how soon a click followed the
            // last one rather than by waiting to find out. A `Button` still
            // cannot do this: its action fires on the first click of a pair,
            // and it would swallow the drag besides.
            .onTapGesture(perform: onClick)
            .onHover { hovering in
                withAnimation(HUDTokens.fade) { isHovered = hovering }
            }
            // Carrying a file out of the shelf. A real file URL, unlike the
            // review window's drag, which vends a move id because it is an
            // internal correction rather than a handover to another app.
            .onDrag {
                onDragStart()
                return NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
            }
            // Simultaneous, so that holding still previews and holding then
            // moving drags. The two gestures begin identically, which is why
            // a plain `onLongPressGesture` here would swallow the drag — the
            // same conflict, and the same fix, as the review window's rows.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        guard entry.isOpenable else { return }
                        onPreview()
                    }
            )
            .contextMenu {
                // Named for what it will actually do, which is no longer the
                // same verb for both kinds of row.
                if row.isEnterable {
                    Button(row.isOpen ? "Close" : "Open Here", action: onToggle)
                    Button("Go Into", action: onOpen)
                } else {
                    Button("Open", action: onOpen)
                }
                Button("Show in Finder", action: onReveal)
            }
            .help(helpText)
    }

    private var line: some View {
        HStack(spacing: 7) {
            Color.clear.frame(width: CGFloat(row.depth) * Self.indent, height: 1)

            twist

            Image(systemName: entry.symbolName)
                .font(.system(size: 11))
                // A folder is the brighter of the two: it is a place, and
                // places are what the eye looks for first in a list.
                .foregroundStyle(entry.isFolder ? HUDTokens.secondaryText : HUDTokens.tertiaryText)
                .frame(width: Self.glyphWidth)

            Text(entry.name)
                .font(HUDTokens.caption)
                .foregroundStyle(isSelected ? HUDTokens.onDark : HUDTokens.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isCloudPlaceholder {
                // Safety rule 5, said on the row rather than only enforced
                // underneath it: this one is not on the disk, so nothing here
                // will open it.
                Image(systemName: "icloud")
                    .font(.system(size: 10))
                    .foregroundStyle(HUDTokens.tertiaryText)
            }

            Text(entry.sizeLabel)
                .font(HUDTokens.caption3)
                .foregroundStyle(HUDTokens.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: Self.sizeWidth, alignment: .trailing)

            Text(age)
                .font(HUDTokens.caption3)
                .foregroundStyle(HUDTokens.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: Self.ageWidth, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: HUDTokens.shelfRowHeight)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: HUDTokens.radiusRow, style: .continuous)
        )
    }

    /// The disclosure triangle.
    ///
    /// A `Button` inside the row rather than another gesture on it, so that
    /// clicking the triangle opens the folder and clicking anywhere else on
    /// the same row still picks it — two different answers in 26 points of
    /// height, which only works if one of them is a real control.
    @ViewBuilder
    private var twist: some View {
        switch row.disclosure {
        case .plain:
            Color.clear.frame(width: Self.twistWidth, height: 1)
        case .open, .closed:
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(HUDTokens.secondaryText)
                    .rotationEffect(.degrees(row.isOpen ? 90 : 0))
                    .frame(width: Self.twistWidth, height: HUDTokens.shelfRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(HUDTokens.fade, value: row.isOpen)
            .help(row.isOpen ? "Close \(entry.name)" : "Open \(entry.name) here")
        }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(HUDTokens.tileHover) }
        if isHovered { return AnyShapeStyle(HUDTokens.tile) }
        return AnyShapeStyle(Color.clear)
    }

    /// Three rows, three sentences. A folder is not previewed and a file in
    /// the cloud is not touched at all, and a tooltip that said otherwise
    /// would be the interface promising something the rules refuse.
    private var helpText: String {
        guard entry.isOpenable else {
            return "\(entry.name) — in iCloud and not downloaded, so Hoot will not open it"
        }
        if entry.isEnterable {
            return "\(entry.name) — space opens it here, double-click goes into it, "
                + "drag to move it"
        }
        return "\(entry.name) — space to preview, double-click to open, drag to move it"
    }
}

/// The footer's small controls.
///
/// Three weights, which is what the design draws: `solid` for the one action
/// that leaves the shelf and does something, `tile` for the ordinary one, and
/// `ghost` for the control that only changes what you are looking at.
struct NotchPill: View {
    enum Tone { case solid, tile, ghost }

    var symbol: String?
    let label: String
    var tone: Tone = .ghost
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                }
                Text(label)
                    .font(HUDTokens.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .frame(height: HUDTokens.pillHeight)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .solid: return HUDTokens.ground
        case .tile: return HUDTokens.onDark
        case .ghost: return HUDTokens.secondaryText
        }
    }

    private var fill: AnyShapeStyle {
        switch tone {
        case .solid: return AnyShapeStyle(HUDTokens.onDark)
        case .tile: return AnyShapeStyle(HUDTokens.tile)
        case .ghost: return AnyShapeStyle(Color.clear)
        }
    }
}
