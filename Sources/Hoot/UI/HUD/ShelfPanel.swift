import SwiftUI
import HootKit

/// The folders you chose, listed at the notch.
///
/// Everything printed here is computed on `FileShelf`, in the engine, where
/// the suite can assert it. This file decides where things sit and nothing
/// about what they say — which is the arrangement the surface this replaces
/// was rebuilt to reach.
struct ShelfPanel: View {
    let shelf: FileShelf
    let untidy: Int
    let now: Date

    var onShowFolder: (Int) -> Void
    var onSelect: (String) -> Void
    var onCycleSort: () -> Void
    var onReveal: () -> Void
    var onTidy: () -> Void
    var onPreview: (URL) -> Void = { _ in }
    var onDragStart: () -> Void = {}
    var onRevealEntry: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if shelf.rows.isEmpty {
                Text(shelf.emptyMessage)
                    .font(HUDTokens.caption)
                    .foregroundStyle(HUDTokens.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: HUDTokens.shelfRowHeight * 2, alignment: .center)
            } else {
                list
            }

            Rectangle()
                .fill(HUDTokens.hairline)
                .frame(height: 1)

            footer
        }
    }

    // MARK: - Which folder

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(Array(shelf.folders.enumerated()), id: \.element.id) { index, folder in
                NotchTab(label: folder.name, isSelected: index == shelf.showing) {
                    onShowFolder(index)
                }
            }

            Spacer(minLength: 8)

            Text(shelf.accessory)
                .font(HUDTokens.caption3)
                .foregroundStyle(HUDTokens.tertiaryText)
                .monospacedDigit()
                .fixedSize()
        }
        .frame(minHeight: HUDTokens.tabHeight)
    }

    // MARK: - What is in it

    /// A definite height, from `HUDPlacement.listHeight` by way of the shelf.
    /// Without one the hosting view reports whatever the list would like to
    /// be, and the window is sized from that — a folder of two hundred files
    /// would ask for a window taller than the display.
    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(shelf.rows) { entry in
                    ShelfRow(
                        entry: entry,
                        isSelected: shelf.selected == entry.id,
                        age: entry.ageLabel(now: now),
                        onSelect: { onSelect(entry.id) },
                        onPreview: { onPreview(entry.url) },
                        onDragStart: onDragStart,
                        onReveal: { onRevealEntry(entry.url) }
                    )
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(height: shelf.listHeight)
    }

    // MARK: - What to do about it

    private var footer: some View {
        HStack(spacing: 8) {
            NotchPill(symbol: "arrow.up.arrow.down", label: shelf.sort.label, tone: .ghost) {
                onCycleSort()
            }
            .help("Change the order")

            Spacer(minLength: 8)

            if let detail = shelf.selectionDetail(now: now) {
                Text(detail)
                    .font(HUDTokens.caption3)
                    .foregroundStyle(HUDTokens.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }

            NotchPill(label: shelf.revealLabel, tone: .tile, action: onReveal)

            // The organizer's one appearance here, and only for the folder
            // there is a plan for — which is the watched folder and no other.
            if let tidyLabel = shelf.tidyLabel(untidy: untidy) {
                NotchPill(label: tidyLabel, tone: .solid, action: onTidy)
                    .help("Open the review window for these")
            }
        }
    }
}
