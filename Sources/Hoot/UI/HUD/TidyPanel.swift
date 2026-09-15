import SwiftUI
import HootKit

/// One group's worth of decision: the folder, why these files belong in it,
/// and what each of them would be called afterwards.
///
/// Both questions are on screen together because they are answered together.
/// A file whose name says nothing is usually also one you cannot place by
/// looking at it, so splitting them would mean asking about the same file
/// twice on two different screens.
///
/// Laid out as the design has it: the reading on the left, the three
/// decisions on the right, a hairline between them. The decisions are round
/// icons with captions rather than labelled buttons — a panel this wide has
/// room for three of one and not three of the other.
struct TidyPanel: View {
    let step: TidyStep
    let isWorking: Bool
    let progress: Double

    var onToggleFile: (UUID) -> Void
    var onApply: () -> Void
    var onSkip: () -> Void
    var onToggleRenaming: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            reading
            Rectangle()
                .fill(HUDTokens.hairline)
                .frame(width: 1)
            decisions
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - What is being proposed

    private var reading: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(HUDTokens.secondaryText)
                    Text(step.group.name)
                        .font(HUDTokens.bodyMedium)
                        .foregroundStyle(HUDTokens.onDark)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(step.pickedSentence)
                    .font(HUDTokens.caption2)
                    .foregroundStyle(HUDTokens.tertiaryText)
                    .monospacedDigit()
                    .fixedSize()
            }

            // Why these files are together. The suggestion is only worth
            // accepting if the reason is, so it is never hidden behind a
            // disclosure.
            Text(step.group.reason)
                .font(HUDTokens.caption2)
                .foregroundStyle(HUDTokens.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)

            VStack(spacing: 0) {
                ForEach(step.rows) { row in
                    // The second column only exists when it has something to
                    // say. With renaming off, or with nothing in this folder
                    // that Hoot could name, it printed the same words on
                    // every row about a thing that was not going to happen.
                    TidyRow(row: row, showsRenaming: step.showsProposedNames) {
                        onToggleFile(row.file.moveID)
                    }
                }
            }
            .padding(.top, 8)

            if isWorking { working }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bar that fills as files actually land, and the word that says
    /// where the work is happening.
    private var working: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(HUDTokens.tile)
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(HUDTokens.onDark)
                            .frame(width: proxy.size.width * progress)
                    }
                }
            // Named, because it is the whole promise: the model that read
            // these files runs here and nothing was uploaded.
            Text("on-device")
                .font(HUDTokens.caption2)
                .foregroundStyle(HUDTokens.tertiaryText)
                .fixedSize()
        }
        .padding(.top, 8)
    }

    // MARK: - What to do about it

    private var decisions: some View {
        HStack(alignment: .top, spacing: 10) {
            NotchAction(
                symbol: "checkmark.circle.fill",
                label: isWorking ? "Filing…" : step.actionLabel,
                tone: .confident,
                isEnabled: step.canApply && !isWorking,
                // The count lives here rather than under the button, where
                // there is room for two words and no more.
                help: step.primaryLabel,
                action: onApply
            )

            NotchAction(
                symbol: "xmark.circle.fill",
                label: "Leave",
                isEnabled: !isWorking,
                help: "Leave this folder's files where they are",
                action: onSkip
            )

            // The one setting that belongs beside the decision rather than in
            // Settings: whether the new names travel with the move. Off is
            // drawn as a ghost rather than hidden — a control that vanishes
            // when you turn it off cannot be turned back on.
            NotchAction(
                symbol: step.isRenaming ? "checkmark.circle.fill" : "circle",
                label: "Rename",
                tone: step.isRenaming ? .standard : .ghost,
                isEnabled: !isWorking,
                help: step.isRenaming
                    ? "New names are applied along with the move"
                    : "Files keep the names they have",
                action: onToggleRenaming
            )
        }
        .fixedSize()
    }
}

// MARK: - One file

/// A file, its proposed name, and the name it is replacing.
///
/// Clicking the row drops the file from this group rather than deleting
/// anything — Hoot never removes a file, and "not this one" has to be
/// expressible without the word delete appearing anywhere near it.
///
/// Three columns on one line, at the design's proportions. The old name gets
/// the narrower share and is allowed to truncate: it is the name that failed
/// to say anything, so it is the one that can afford to lose its middle.
private struct TidyRow: View {
    let row: TidyFileRow
    /// Whether the second column is worth its width. With renaming off there
    /// is no old name to strike out and nothing to say about one, so the
    /// filename takes the whole row instead.
    let showsRenaming: Bool
    let onToggle: () -> Void

    /// The design's `minmax(0, 1.25fr) minmax(0, 1fr)`: the new name gets the
    /// larger share because it is the one being proposed, and both shares are
    /// fixed fractions so neither column can push the other off the row.
    /// Laid out against the measured width rather than by layout priority —
    /// priority hands the first view its whole ideal width, and a long
    /// filename then leaves nothing at all for the name it replaces.
    private static let newNameShare: CGFloat = 1.25 / 2.25

    private static let tickWidth: CGFloat = 12
    private static let kindWidth: CGFloat = 14
    private static let gap: CGFloat = 6

    var body: some View {
        Button(action: onToggle) {
            GeometryReader { proxy in
                let gaps = Self.gap * (showsRenaming ? 3 : 2)
                let columns = max(
                    proxy.size.width - Self.tickWidth - Self.kindWidth - gaps, 0
                )
                HStack(spacing: Self.gap) {
                    Image(systemName: row.isKept ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(row.isKept ? HUDTokens.onDark : HUDTokens.tertiaryText)
                        .frame(width: Self.tickWidth)

                    // What kind of file it is, which is faster to take in as a
                    // shape than to read out of a name — especially when the
                    // name is the thing that failed to say anything.
                    Image(systemName: row.file.kindSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(HUDTokens.tertiaryText)
                        .frame(width: Self.kindWidth)

                    Text(row.shownName)
                        .font(HUDTokens.caption)
                        .foregroundStyle(row.isKept ? HUDTokens.onDark : HUDTokens.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(
                            width: showsRenaming ? columns * Self.newNameShare : columns,
                            alignment: .leading
                        )

                    if showsRenaming {
                        Text(row.replacedName ?? row.subLead)
                            .font(HUDTokens.mono)
                            .foregroundStyle(HUDTokens.tertiaryText)
                            .strikethrough(row.replacedName != nil, color: HUDTokens.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: columns * (1 - Self.newNameShare), alignment: .leading)
                    }
                }
                .frame(height: proxy.size.height)
            }
            .padding(.horizontal, 3)
            .frame(height: HUDTokens.fileRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.isKept ? 1 : 0.45)
        .animation(HUDTokens.fade, value: row.isKept)
        .help(row.isKept ? "Leave this one out" : "Put this one back")
    }
}
