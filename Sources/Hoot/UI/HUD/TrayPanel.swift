import SwiftUI
import HootKit

/// What is waiting, as a quantity rather than a list.
///
/// The Tidy tab answers "should this folder happen"; this one answers the
/// question people actually ask a menu bar app twenty times a day — "is
/// anything piling up, and how long has it been there". Tiles rather than
/// rows because six tiles read as an amount at a glance, where six filenames
/// have to be read one at a time.
struct TrayPanel: View {
    let title: String
    let detail: String
    let files: [TidyFile]
    /// What to print under each tile, worked out across the whole set rather
    /// than per file — see `TidyFlow.trayCaptions`. A row of tiles that all
    /// arrived the same evening needs clock times, not five identical ages.
    let captions: [UUID: String]
    let onSortAll: () -> Void

    /// Five, then a count. A sixth tile would push the panel wider than the
    /// design allows and say nothing the "+4" does not.
    private static let shownTiles = 5

    private var shown: [TidyFile] { Array(files.prefix(Self.shownTiles)) }
    private var overflow: Int { max(0, files.count - Self.shownTiles) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(HUDTokens.bodyMedium)
                        .foregroundStyle(HUDTokens.onDark)
                        .monospacedDigit()
                        .fixedSize()

                    Text(detail)
                        .font(HUDTokens.caption2)
                        .foregroundStyle(HUDTokens.tertiaryText)
                        .lineLimit(1)
                }

                HStack(alignment: .top, spacing: 8) {
                    ForEach(shown) { file in
                        NotchFileTile(
                            symbol: file.kindSymbol,
                            name: file.currentName,
                            caption: captions[file.moveID]
                        )
                    }
                    if overflow > 0 {
                        NotchMoreTile(count: overflow)
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(HUDTokens.hairline)
                .frame(width: 1)

            NotchAction(
                symbol: "arrow.turn.down.right",
                label: "Sort all",
                help: "Start filing these, one folder at a time",
                action: onSortAll
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
