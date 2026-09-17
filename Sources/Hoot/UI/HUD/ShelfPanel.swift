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
    /// What was just handed to the Finder or the review window, if anything.
    var handoff: String?
    var onDismissHandoff: () -> Void = {}
    /// The standard places, offered as tabs before they have been granted.
    var offers: [(name: String, url: URL)] = []
    var onAddFolder: (URL?) -> Void = { _ in }
    var onRemoveFolder: (URL) -> Void = { _ in }

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

            if let handoff {
                handoffBanner(handoff)
            }

            if shelf.rows.isEmpty {
                Text(shelf.isEmpty
                     ? "Pick a folder above and it will be listed here."
                     : shelf.emptyMessage)
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
        // The design's minimum. Without it a folder holding one file gives a
        // panel barely taller than the housing it grew out of, which reads as
        // the thing having failed to open rather than as a short list.
        .frame(minHeight: 112, alignment: .top)
    }

    /// Said rather than assumed.
    ///
    /// Revealing a file and opening the review window are the two things the
    /// panel does whose result appears somewhere else entirely — and from
    /// inside the panel they look exactly like a button that did nothing.
    private func handoffBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(HUDTokens.confident)
            Text(message)
                .font(HUDTokens.caption2)
                .foregroundStyle(HUDTokens.onDark)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            NotchPill(label: "Dismiss", tone: .ghost, action: onDismissHandoff)
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(
            HUDTokens.tile,
            in: RoundedRectangle(cornerRadius: HUDTokens.radiusRow, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HUDTokens.radiusRow, style: .continuous)
                .strokeBorder(HUDTokens.hairline)
        )
    }

    // MARK: - Which folder

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(Array(shelf.folders.enumerated()), id: \.element.id) { index, folder in
                NotchTab(label: folder.name, isSelected: index == shelf.showing) {
                    onShowFolder(index)
                }
                // Taking a folder off the shelf belongs where the folder is,
                // not only in Settings: the tab is the thing you are looking
                // at when you decide you no longer want it.
                .contextMenu {
                    Button("Remove \(folder.name) from Shelf") {
                        onRemoveFolder(folder.url)
                    }
                }
            }

            // Behind a menu, not beside the real tabs.
            //
            // These were dimmed tabs for one build, and a dimmed tab beside
            // an unselected one is no signal at all: adding Desktop looked
            // like it had added Documents, Downloads and Pictures too. A tab
            // row should only ever contain folders that are actually there.
            if shelf.hasRoom {
                Menu {
                    ForEach(offers, id: \.url) { offer in
                        Button("Add \(offer.name)") { onAddFolder(offer.url) }
                    }
                    if !offers.isEmpty { Divider() }
                    Button("Choose Folder…") { onAddFolder(nil) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HUDTokens.secondaryText)
                        .frame(width: 22, height: HUDTokens.tabHeight)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a folder to the shelf")
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
            NotchPill(symbol: "arrow.turn.down.right", label: shelf.sort.label, tone: .ghost) {
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
