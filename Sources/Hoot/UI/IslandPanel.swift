import AppKit
import SwiftUI
import Combine
import HootKit

/// Hosts the island in a floating panel under the notch.
///
/// macOS has no Dynamic Island — that is iPhone hardware — so this is a
/// borderless panel positioned where one would be. Non-activating on purpose:
/// pointing at it must never pull focus out of whatever the person is actually
/// doing, which is the difference between an ambient indicator and an
/// interruption.
@MainActor
final class IslandController {
    private var panel: NSPanel?
    /// Created once and then fed new root views, so the island's hover state
    /// survives every refresh that isn't about hovering.
    private var hosting: NSHostingView<IslandView>?
    private var frameObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private let appState: AppState

    /// Set when the person waves the island away, cleared when the situation
    /// genuinely changes, so "Later" means later rather than never.
    private var dismissedSignature: String?

    init(appState: AppState) {
        self.appState = appState
        observe()
    }

    private func observe() {
        // One republish for any of the inputs the island reads.
        Publishers.CombineLatest4(
            appState.$detectedFiles,
            appState.$lastMessage,
            appState.$batches,
            // The mode is one of the island's inputs now, so changing it from
            // the island has to redraw the island.
            appState.$sortingMode
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in self?.refresh() }
        .store(in: &cancellables)
    }

    private func currentState() -> IslandState? {
        if let message = appState.lastMessage, appState.detectedFiles.isEmpty {
            return .organized(message: message, canUndo: appState.canUndo)
        }
        let waiting = appState.detectedFiles.count
        guard waiting > 0 else { return nil }
        let groups = appState.summaryByCategory
            .map { IslandGroup(name: $0.label, count: $0.count) }
        return .waiting(count: waiting, groups: groups)
    }

    /// A short description of *what* is being shown, so a dismissal sticks to
    /// that situation and not to the next one.
    private func signature(of state: IslandState) -> String {
        switch state {
        case .waiting(let count, _): return "waiting-\(count)-\(appState.sortingMode.rawValue)"
        case .organized(let message, _): return "organized-\(message)"
        }
    }

    func refresh() {
        guard let state = currentState() else { return hide() }
        guard signature(of: state) != dismissedSignature else { return hide() }
        show(state)
    }

    private func show(_ state: IslandState) {
        let view = IslandView(
            state: state,
            mode: appState.sortingMode,
            notch: Self.notchMetrics(for: NSScreen.main),
            onSelectMode: { [weak self] mode in
                // Deliberately not a dismissal: the person is adjusting what
                // they are looking at, not saying they are done with it.
                self?.appState.sortingMode = mode
            },
            onReview: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.appState.presentWindow?(WindowID.review)
                self?.dismiss(state)
            },
            onUndo: { [weak self] in
                self?.appState.undoLast()
                self?.dismiss(state)
            },
            onDismiss: { [weak self] in self?.dismiss(state) }
        )

        // Replacing the root view rather than the hosting view keeps the
        // island's own `@State` alive. It matters as soon as the panel has
        // anything to click: choosing a sorting mode changes app state, which
        // comes straight back here as a refresh — and a fresh hosting view
        // would arrive collapsed, snapping shut under the pointer that just
        // used it. It also stops a frame observer being added per refresh.
        if let hosting {
            hosting.rootView = view
            panel?.orderFrontRegardless()
            return
        }

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)
        self.hosting = hosting

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        self.panel = panel

        // Size to the content's collapsed footprint, then let the panel grow
        // with it: a fixed panel would either clip the expanded state or leave
        // an invisible rectangle swallowing clicks around the collapsed one.
        resize(panel, to: hosting.fittingSize)
        panel.orderFrontRegardless()

        // The hosting view resizes itself when the SwiftUI content grows. AppKit
        // stretches the panel to match, but keeps its bottom-left corner fixed,
        // so an island that grew would climb into the menu bar instead of
        // hanging below it. This is what puts the top edge back.
        //
        // Deferred to the next turn of the run loop, and that is not a
        // nicety. The notification arrives *inside* AppKit's layout pass, and
        // setting a window frame from within one re-enters it: NSHostingView
        // invalidates its size constraints, AppKit reaches
        // -[NSWindow _postWindowNeedsUpdateConstraints] while it is already
        // updating them, and throws. The exception is uncaught, so the app
        // does not misbehave — it dies, every time the island changes size.
        hosting.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: hosting, queue: .main
        ) { [weak self, weak panel, weak hosting] _ in
            guard let panel, let hosting else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.resize(panel, to: hosting.fittingSize) }
            }
        }
    }

    /// Reads the shape of the display's top edge.
    ///
    /// `safeAreaInsets.top` gives the cutout's height. Its width is not
    /// published directly, but the system reports the two strips of menu bar
    /// it leaves usable either side of it — so the gap between them is the
    /// notch.
    static func notchMetrics(for screen: NSScreen?) -> NotchMetrics {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return .none }
        return NotchMetrics(
            height: screen.safeAreaInsets.top,
            width: max(0, right.minX - left.maxX),
            centerX: (left.maxX + right.minX) / 2
        )
    }

    private func resize(_ panel: NSPanel, to size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let notch = Self.notchMetrics(for: screen)

        // With a notch, the island's top edge is the top of the display: the
        // black continues out of the camera housing instead of hanging under
        // it. Without one there is nothing to continue from, so it sits below
        // the menu bar as before, with a gap that reads as deliberate.
        let top = notch.hasNotch
            ? screen.frame.maxY
            : screen.visibleFrame.maxY
        let gap: CGFloat = notch.hasNotch ? 0 : 6

        // Centred on the camera, not on the screen. They are half a point
        // apart on this hardware, which is enough to show as a seam.
        let centerX = notch.hasNotch ? notch.centerX : screen.frame.midX
        let origin = NSPoint(
            x: centerX - size.width / 2,
            y: top - size.height - gap
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = IslandWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // the capsule draws its own
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Visible on every space and over full-screen apps: a folder fills up
        // while you are working, which is usually somewhere else.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private func dismiss(_ state: IslandState) {
        dismissedSignature = signature(of: state)
        hide()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    deinit {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }
}

/// A panel allowed to reach the top of the screen.
///
/// AppKit constrains window frames so they cannot cover the menu bar. That is
/// right for windows and wrong for this one: the island's whole premise is
/// that it continues from the camera housing, and a frame stopped 34pt short
/// of the display's top edge leaves it floating under the notch instead.
private final class IslandWindow: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
