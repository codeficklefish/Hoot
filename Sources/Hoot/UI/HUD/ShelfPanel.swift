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
    var onPreview: (ShelfRowItem) -> Void = { _ in }
    var onToggleFolder: (ShelfRowItem) -> Void = { _ in }
    var onDragStart: () -> Void = {}
    var onRevealEntry: (URL) -> Void = { _ in }
    var onOpenEntry: (ShelfEntry) -> Void = { _ in }
    var onLeaveFolder: () -> Void = {}
    var onReturnToRoot: () -> Void = {}

    /// Where the pointer is on the tab row, and the wait it started.
    ///
    /// A box rather than two `@State` values, and that is the whole point.
    /// Writing to `@State` from inside a hover handler re-renders the tab row
    /// *from its parent*, which is this view — and a row rebuilt under the
    /// pointer reports that the pointer left it. The departure cancelled the
    /// wait the arrival had just started, the re-entry started another, and
    /// the folder never changed. A box is mutated without the view changing,
    /// so pointing at a tab no longer redraws the thing being pointed at.
    @State private var hover = TabHover()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let folder = shelf.current, !folder.isAtRoot {
                breadcrumb(folder)
            }

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

    /// Where you are, once you are not at the tab.
    ///
    /// Absent at the root rather than showing the folder's own name, because
    /// the tab above is already saying it — and a line that is always there
    /// stops being read. It appearing *is* the signal that going back is now
    /// a thing you might want to do.
    private func breadcrumb(_ folder: ShelfFolder) -> some View {
        HStack(spacing: 6) {
            NotchPill(symbol: "chevron.left", label: "Up", tone: .tile, action: onLeaveFolder)
                .help("Back to \(folder.parent?.lastPathComponent ?? folder.name)")

            Button(action: onReturnToRoot) {
                Text(folder.trailLabel)
                    .font(HUDTokens.caption3)
                    .foregroundStyle(HUDTokens.tertiaryText)
                    .lineLimit(1)
                    // The end is the part that changes and the part you are
                    // in, so the front is what gets dropped.
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to \(folder.name)")
        }
        .frame(height: HUDTokens.pillHeight)
    }

    // MARK: - Which folder

    private var header: some View {
        HStack(spacing: 4) {
            tabs

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

    /// The folders, at full width, in a row that moves rather than squeezes.
    ///
    /// Scrolled to follow the selection rather than by the pointer: the HUD's
    /// scroll monitor takes horizontal gestures over the panel for paging
    /// between folders, so a row that expected to be swiped would never
    /// receive one. Paging and this are the same motion from the user's side
    /// — change folder, and the row brings that tab into view.
    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(shelf.folders.enumerated()), id: \.element.id) { index, folder in
                        NotchTab(
                            label: folder.name,
                            isSelected: index == shelf.showing,
                            onHover: { point(at: index, $0) },
                            action: { show(index) }
                        )
                        .help("Show \(folder.name)")
                        // Taking a folder off the shelf belongs where the
                        // folder is, not only in Settings: the tab is the
                        // thing you are looking at when you decide you no
                        // longer want it.
                        .contextMenu {
                            Button("Remove \(folder.name) from Shelf") {
                                onRemoveFolder(folder.root)
                            }
                        }
                        .id(folder.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: HUDTokens.tabHeight)
            .onChange(of: shelf.showing) { _ in
                // Not while the pointer is on the row. The tabs move under it
                // otherwise, which puts a *different* folder under the cursor
                // — and that is another hover, and another folder, and the
                // row walks itself along. Somebody pointing at the tabs can
                // already see them; this is for the swipe and the hot keys,
                // where the row is the only thing that says where you are.
                guard hover.pointingAt == nil, let current = shelf.current else { return }
                withAnimation(HUDTokens.resize) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
            .onDisappear { hover.cancel() }
        }
    }

    // MARK: - Pointing at a tab

    /// Pointing at a folder lists it, once the pointer has stayed.
    ///
    /// The wait is the whole design. Clicking a tab is unambiguous; crossing
    /// one on the way to the `+` beside it is not, and switching on contact
    /// would change the folder three times on one trip along the row. The
    /// shelf owns how long "stayed" is, and whether this tab is worth
    /// switching to at all.
    private func point(at index: Int, _ isInside: Bool) {
        HUDTrace.say("tab \(index) \(isInside ? "entered" : "left")")

        guard isInside else {
            // Only when this is still the tab being waited on. Sliding from
            // one tab to the next can deliver the arrival before the
            // departure, and cancelling on the late "left the last one" would
            // kill the wait that had just started on the new one — leaving a
            // pointer sitting on a tab that never opens.
            guard hover.pointingAt == index else { return }
            hover.pointingAt = nil
            hover.cancel()
            return
        }

        hover.pointingAt = index
        guard shelf.shouldShow(folderAt: index) else {
            hover.cancel()
            return
        }

        hover.begin(after: FileShelf.hoverDwell) {
            HUDTrace.say("tab \(index) waited out, showing it")
            onShowFolder(index)
        }
    }

    /// A click says the same thing the dwell would have, immediately — so the
    /// pending one is dropped rather than left to fire again behind it.
    private func show(_ index: Int) {
        hover.cancel()
        onShowFolder(index)
    }

    // MARK: - What is in it

    /// A definite height, from `HUDPlacement.listHeight` by way of the shelf.
    /// Without one the hosting view reports whatever the list would like to
    /// be, and the window is sized from that — a folder of two hundred files
    /// would ask for a window taller than the display.
    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(shelf.rows) { row in
                    ShelfRow(
                        row: row,
                        isSelected: shelf.selected == row.id,
                        age: row.entry.ageLabel(now: now),
                        onSelect: { onSelect(row.id) },
                        onPreview: { onPreview(row) },
                        onDragStart: onDragStart,
                        onReveal: { onRevealEntry(row.url) },
                        onOpen: { onOpenEntry(row.entry) },
                        onToggle: { onToggleFolder(row) }
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

/// The pointer's place on the tab row, and the wait it started.
///
/// A reference on purpose — see `ShelfPanel.hover`. Hover bookkeeping that
/// lives in `@State` redraws the row it is bookkeeping for, and a tab redrawn
/// under the pointer reports a departure that never happened.
@MainActor
final class TabHover {
    /// The tab the pointer is on, or nil. Read by the tab row, which holds
    /// still rather than scrolling a different folder under a stationary
    /// cursor.
    var pointingAt: Int?

    private var task: Task<Void, Never>?

    func begin(after seconds: TimeInterval, then act: @escaping () -> Void) {
        cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            act()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
