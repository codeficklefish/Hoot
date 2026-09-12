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
        Publishers.CombineLatest3(
            appState.$detectedFiles,
            appState.$lastMessage,
            appState.$batches
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in self?.refresh() }
        .store(in: &cancellables)
    }

    private func currentState() -> IslandState? {
        if let message = appState.lastMessage, appState.detectedFiles.isEmpty {
            return .organized(message: message, canUndo: appState.canUndo)
        }
        let waiting = appState.detectedFiles.count
        guard waiting > 0 else { return nil }
        let groups = appState.summaryByCategory.map(\.label)
        return .waiting(count: waiting, groups: groups)
    }

    /// A short description of *what* is being shown, so a dismissal sticks to
    /// that situation and not to the next one.
    private func signature(of state: IslandState) -> String {
        switch state {
        case .waiting(let count, _): return "waiting-\(count)"
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

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        self.panel = panel

        // Size to the content's collapsed footprint, then let the panel grow
        // with it: a fixed panel would either clip the expanded state or leave
        // an invisible rectangle swallowing clicks around the collapsed one.
        resize(panel, to: hosting.fittingSize)
        panel.orderFrontRegardless()

        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: hosting, queue: .main
        ) { [weak self, weak panel, weak hosting] _ in
            guard let panel, let hosting else { return }
            MainActor.assumeIsolated { self?.resize(panel, to: hosting.fittingSize) }
        }
    }

    private func resize(_ panel: NSPanel, to size: NSSize) {
        guard let screen = NSScreen.main else { return }
        // Below the menu bar, and below the notch where there is one —
        // safeAreaInsets.top is how a notched display says how tall it is.
        let notch = screen.safeAreaInsets.top
        let top = screen.frame.maxY - max(notch, screen.frame.maxY - screen.visibleFrame.maxY)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: top - size.height - 6
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
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
}
