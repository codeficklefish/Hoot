import SwiftUI
import HootKit

/// One proposed move, and the evidence behind it.
///
/// Kept apart from the review screen itself: this is where a person decides
/// whether they believe a single suggestion, which is a different job from
/// laying out the list.

struct MoveRow: View {
    let move: PlannedMove
    @ObservedObject var appState: AppState

    /// The file Quick Look is showing, owned by the review screen so only one
    /// panel exists however many rows are on screen.
    @Binding var previewURL: URL?

    /// Evidence is hidden until asked for: most of the time the destination is
    /// all anyone wants, but when a suggestion looks wrong the reasoning is
    /// the difference between correcting it and distrusting the whole app.
    @State private var isShowingEvidence = false

    /// Whether the pointer is on this row. Drives the highlight and the
    /// disclosure chevron, which stays out of the way until there is a reason
    /// to think about this particular file.
    @State private var isHovered = false

    private var isDemoted: Bool {
        move.roleSubfolder == OrganizationPlanner.demotedSubfolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { move.isApproved },
                    set: { appState.setApproval($0, forMove: move.id) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: move.file.kind.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(move.file.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 8)

                if isDemoted {
                    Label("older version", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("A newer version exists. Hoot keeps this one — it just moves it out of the way rather than deleting it.")
                }

                ConfidenceDot(confidence: move.classification.confidence)

                Button {
                    withAnimation(Motion.state) { isShowingEvidence.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        // Rotated rather than swapped: the same mark turning
                        // reads as one control changing state, where two
                        // different glyphs read as the row being replaced.
                        .rotationEffect(.degrees(isShowingEvidence ? 90 : 0))
                        .opacity(isHovered || isShowingEvidence ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .help("Why here?")
            }

            if isShowingEvidence {
                EvidencePanel(move: move, excerpt: appState.evidence[move.file.id])
                    .padding(.leading, 22)
                    // Opens downward from the row it belongs to rather than
                    // fading in over whatever is beneath it.
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(.callout)
        .opacity(isDemoted ? 0.55 : 1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .hoverHighlight(isHovered)
        .onHover { hovering in
            withAnimation(Motion.hover) { isHovered = hovering }
        }
        // Dragging a file to another folder is the natural way to say "not
        // there, here" — and it is the correction Hoot learns from.
        .onDrag {
            NSItemProvider(object: move.id.uuidString as NSString)
        }
        // Hold still to look inside the file. Deciding whether a suggestion is
        // right often means checking what the file actually is, and the
        // filename is the thing that failed to say.
        //
        // Simultaneous, and long-press cancels once the pointer moves: holding
        // still previews, holding and moving drags. The two gestures start the
        // same way, so a plain onLongPressGesture would swallow the drag.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in previewURL = move.file.url }
        )
        .help("Hold to preview")
    }
}

/// Confidence at a glance, with the reasoning behind it on hover.
struct ConfidenceDot: View {
    let confidence: Double

    private var color: Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .help("\(Int(confidence * 100))% confident")
    }
}

/// What the suggestion actually rests on.
struct EvidencePanel: View {
    let move: PlannedMove
    let excerpt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(move.classification.reason, systemImage: "lightbulb")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let excerpt, !excerpt.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read from inside the file")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(excerpt.prefix(220) + (excerpt.count > 220 ? "…" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(move.destinationSubpath + "/" + move.destinationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Drag this file onto another folder to correct it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}
