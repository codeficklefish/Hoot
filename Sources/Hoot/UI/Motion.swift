import SwiftUI

/// Movement that reports what the app is doing, rather than decorating it.
///
/// Three rules hold everything here together. Motion answers something the
/// user did, so nothing animates on its own. It is short — long enough to be
/// followed, never long enough to be waited for. And it is a hint at the
/// edges rather than a performance in the middle, because the review list is
/// something people read, and text that swims while being read is worse than
/// text that sits still.
enum Motion {
    /// For anything the pointer causes: hover, press. Fast enough to feel
    /// like a property of the control rather than a response to it.
    static let hover = Animation.easeOut(duration: 0.12)

    /// For state the user changed: a row approved, a section opened.
    static let state = Animation.easeInOut(duration: 0.18)

    /// For things arriving and leaving — a file dragged into another folder.
    /// Springy, because a row that slides into place explains where it went
    /// in a way a cross-fade does not.
    static let move = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

extension View {
    /// Fades and settles a row as it reaches the edges of a scroll view.
    ///
    /// The point is to make the list feel attached to the scroll rather than
    /// clipped by a rectangle: content arrives rather than appearing. Kept
    /// deliberately slight — a row is readable throughout, and the effect is
    /// gone by the time it reaches the middle of the window.
    ///
    /// `scrollTransition` arrived in macOS 14 and does this against the real
    /// scroll position, which hand-rolled geometry in a lazy stack does badly
    /// and expensively. On 13 there is simply no effect: the list still
    /// scrolls, it just does not fade.
    @ViewBuilder
    func scrollReveal() -> some View {
        if #available(macOS 14.0, *) {
            self.scrollTransition(.interactive, axis: .vertical) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.25)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97, anchor: .center)
                    .offset(y: phase.value * -6)
            }
        } else {
            self
        }
    }

    /// A number that rolls rather than jumps when it changes.
    @ViewBuilder
    func rollingDigits() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    /// A background that appears under the pointer.
    ///
    /// Takes the hover state rather than owning it, so the row can use the
    /// same flag for anything else it wants to reveal.
    func hoverHighlight(_ isHovered: Bool, cornerRadius: CGFloat = 6) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
        )
    }
}
