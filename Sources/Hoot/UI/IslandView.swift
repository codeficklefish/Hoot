import SwiftUI
import HootKit

/// The island's two states.
///
/// Collapsed is a glance: how many files are waiting, nothing more. Expanded
/// is the decision: what Hoot thinks they are, and the one action worth taking.
/// Anything else belongs in the review window, which is a page, not a pill.
enum IslandState: Equatable {
    /// Files have arrived and settled.
    case waiting(count: Int, groups: [String])
    /// A batch just moved, and can still be taken back.
    case organized(message: String, canUndo: Bool)

    var isWaiting: Bool { if case .waiting = self { return true }; return false }
}

/// A capsule that sits under the notch and grows when you point at it.
///
/// Black regardless of appearance, which is the one thing the real Dynamic
/// Island never changes: it reads as a continuation of the hardware rather than
/// a window, and that only holds if it stays the colour of the bezel.
struct IslandView: View {
    let state: IslandState
    var onReview: () -> Void
    var onUndo: () -> Void
    var onDismiss: () -> Void

    @State private var isExpanded = false

    /// Collapsing on exit rather than on a timer: a pointer leaving is the
    /// clearest "I am done with this" a pill can be given.
    private var expanded: Bool { isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
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

            if expanded {
                if case .waiting(_, let groups) = state, !groups.isEmpty {
                    Text(groups.prefix(4).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
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
        .padding(.vertical, expanded ? 14 : 8)
        .background(.black, in: RoundedRectangle(cornerRadius: expanded ? 22 : 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
        .onHover { hovering in
            // The spring is the whole point: the island is recognisable by how
            // it moves, not by being a rounded rectangle.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                isExpanded = hovering
            }
        }
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
