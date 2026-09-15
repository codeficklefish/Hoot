import AppKit
import SwiftUI
import Combine
import HootKit

/// Hosts the HUD in a floating panel over the camera housing.
///
/// macOS has no Dynamic Island — that is iPhone hardware — so this is a
/// borderless panel positioned where one would be, growing out of the notch
/// rather than hanging below it.
///
/// **Notched displays only.** Where there is no cutout there is nothing to
/// continue from, and a black pill floating under the menu bar is just a
/// window someone parked there. The menu bar popover is the whole interface
/// on those Macs, and it is a good one.
@MainActor
final class HUDController: ObservableObject {
    /// Whether the person has the HUD turned on at all. The panel can still
    /// be hidden while this is true — there is simply nothing to say.
    ///
    /// Remembered across launches. Turning a surface on is a decision about
    /// how you want to work, and having to make it again every morning is
    /// how a feature stops being used.
    @Published private(set) var isEnabled = false

    /// Whether the panel is open rather than resting in the housing.
    ///
    /// Held here rather than inside the view, where it started, because two
    /// things outside the view now depend on it: the window has to be resized
    /// to match, and ⌃⌥←/→ are registered system-wide only while the panel is
    /// open, so that those keys belong to whatever the person is working in
    /// for the rest of the time.
    private var isPanelOpen = false

    private static let enabledKey = "hud.enabled"

    private var panel: HUDPanel?
    /// Created once and then fed new root views, so the HUD's hover state
    /// survives every refresh that isn't about hovering.
    private var hosting: NSHostingView<HUDView>?
    private var frameObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    /// Accumulates trackpad travel until it amounts to a page turn. The rule
    /// itself lives in the engine, where it can be checked.
    private var swipe = SwipeTracker()
    /// ⌃⌥←/→, for the same job the swipe does. Registered and given up as the
    /// panel opens and closes.
    private let hotKeys = HUDHotKeys()
    private var cancellables: Set<AnyCancellable> = []

    private var appState: AppState?

    /// True when this Mac has a camera housing to grow out of.
    static var isSupported: Bool {
        Self.notch(for: NSScreen.main).hasNotch
    }

    // MARK: - Turning it on and off

    func enable(appState: AppState) {
        guard Self.isSupported else { return }
        self.appState = appState
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        observe(appState)
        watchForSwipes()
        // A plan may already exist — switching the HUD on should pick it up
        // rather than wait for the folder to change.
        appState.refreshTidyFlow()
        refresh()
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        cancellables.removeAll()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        hotKeys.unregister()
        hide()
    }

    /// Restores the HUD if it was on when the app last quit.
    ///
    /// Called from the app rather than `init`, for the same reason
    /// `AppState.start()` is: this puts a panel on the user's screen, and
    /// nobody should get that merely by constructing one of these.
    func restore(appState: AppState) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        enable(appState: appState)
    }

    func toggle(appState: AppState) {
        isEnabled ? disable() : enable(appState: appState)
    }

    private func observe(_ appState: AppState) {
        cancellables.removeAll()
        // The plan is what the walk is built from; the rest is what the walk
        // itself publishes as it is answered.
        appState.$plan
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                appState.refreshTidyFlow()
                self?.refresh()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            appState.$tidyFlow,
            appState.$isTidyWorking,
            appState.$tidyProgress
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in self?.refresh() }
        .store(in: &cancellables)
    }

    // MARK: - Paging by keyboard
    //
    // The panel never takes keyboard focus — that is what lets it be pointed
    // at mid-sentence — so an ordinary key press never reaches it: keystrokes
    // go to the frontmost application's key window, and Hoot is never
    // frontmost. A registered hot key is the one route that needs none of
    // that, and it is given up the moment the panel closes so the
    // combination goes back to whatever the person is actually using.

    /// The view telling us it has opened or closed.
    ///
    /// Explicit rather than a `didSet`, because the work it does ends in
    /// `refresh()` — which is frequently what set it in the first place, and
    /// a property that re-enters its own caller is a bad thing to leave lying
    /// around for whoever assigns to it next.
    private func setPanelOpen(_ open: Bool) {
        guard isPanelOpen != open else { return }
        isPanelOpen = open
        syncHotKeys()
        refresh()
    }

    private func syncHotKeys() {
        guard isEnabled, isPanelOpen else { return hotKeys.unregister() }
        hotKeys.register { [weak self] page in
            guard let appState = self?.appState else { return }
            switch page {
            case .previous: appState.showPreviousTidyGroup()
            case .next: appState.showNextTidyGroup()
            }
        }
    }

    // MARK: - Paging by swipe
    //
    // A local monitor rather than a SwiftUI gesture: two fingers on a
    // trackpad arrive as `scrollWheel`, which SwiftUI has no gesture for, and
    // a view placed underneath to catch them never sees them either — an
    // unhandled scroll walks up the responder chain, not sideways.

    private func watchForSwipes() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.page(on: event) ?? event }
        }
    }

    /// Returns nil for events the HUD has taken. The panel is not a
    /// scrollable surface, so a sideways flick over it should page it and
    /// stop, never fall through to whatever is underneath.
    private func page(on event: NSEvent) -> NSEvent? {
        guard isEnabled, let panel, event.window === panel, let appState else { return event }

        var phase: SwipeTracker.Phase = .changed
        if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled)
                    || !event.momentumPhase.isEmpty {
            // Momentum is the gesture coasting after the fingers have gone.
            // Counting it would turn one flick into three.
            phase = .ended
        } else if event.phase.isEmpty, event.momentumPhase.isEmpty {
            // A wheel rather than a trackpad: it reports no phases at all, so
            // each event has to stand as its own gesture or the first one
            // would be the last that ever counted.
            _ = swipe.track(deltaX: 0, deltaY: 0, phase: .began)
        }

        guard let direction = swipe.track(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            phase: phase
        ) else { return nil }

        switch direction {
        case .next: appState.showNextTidyGroup()
        case .previous: appState.showPreviousTidyGroup()
        }
        return nil
    }

    // MARK: - What to show

    func refresh() {
        guard isEnabled, let appState, let flow = appState.tidyFlow,
              flow.stage != .idle
        else { return hide() }
        show(flow, appState: appState)
    }

    private func show(_ flow: TidyFlow, appState: AppState) {
        let view = HUDView(
            flow: flow,
            isOpen: Binding(
                get: { [weak self] in self?.isPanelOpen ?? false },
                set: { [weak self] in self?.setPanelOpen($0) }
            ),
            notch: Self.notch(for: NSScreen.main),
            isWorking: appState.isTidyWorking,
            progress: appState.tidyProgress,
            onToggleFile: { appState.toggleTidyFile($0) },
            onApply: { Task { await appState.applyTidyGroup() } },
            onSkip: { appState.skipTidyGroup() },
            onToggleRenaming: { appState.toggleTidyRenaming() },
            onUndo: { appState.undoTidy() },
            onDone: { appState.finishTidy() },
            onShowGroup: { appState.showTidyGroup(at: $0) }
        )

        // Replacing the root view rather than the hosting view keeps the
        // HUD's own `@State` alive. It matters as soon as the panel has
        // anything to click: approving a rename changes app state, which
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

        let panel = self.panel ?? HUDPanel.make()
        panel.contentView = hosting
        self.panel = panel

        // Size to the content's collapsed footprint, then let the panel grow
        // with it: a fixed panel would either clip the expanded state or
        // leave an invisible rectangle swallowing clicks around the
        // collapsed one.
        resize(panel, to: hosting.fittingSize)
        panel.orderFrontRegardless()

        // The hosting view resizes itself when the SwiftUI content grows.
        // AppKit stretches the panel to match, but keeps its bottom-left
        // corner fixed, so a HUD that grew would climb *into* the menu bar
        // instead of hanging below it. This is what puts the top edge back.
        //
        // Deferred to the next turn of the run loop, and that is not a
        // nicety. The notification arrives *inside* AppKit's layout pass,
        // and setting a window frame from within one re-enters it:
        // NSHostingView invalidates its size constraints, AppKit reaches
        // -[NSWindow _postWindowNeedsUpdateConstraints] while it is already
        // updating them, and throws. The exception is uncaught, so the app
        // does not misbehave — it dies, every time the HUD changes size.
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

    private func hide() {
        panel?.orderOut(nil)
        // Straight to the stored value and the hot keys, not through
        // `setPanelOpen`: that ends in `refresh()`, which is usually what
        // called this. A hidden panel is a closed one, and the next one to
        // appear should arrive resting in the housing.
        isPanelOpen = false
        hotKeys.unregister()
    }

    // MARK: - Where it goes

    /// Reads the shape of the display's top edge.
    ///
    /// `safeAreaInsets.top` gives the cutout's height. Its width is not
    /// published directly, but the system reports the two strips of menu bar
    /// it leaves usable either side of it — so the gap between them is the
    /// notch.
    static func notch(for screen: NSScreen?) -> NotchShape {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return .none }
        return NotchShape(
            height: screen.safeAreaInsets.top,
            width: max(0, right.minX - left.maxX),
            centerX: (left.maxX + right.minX) / 2
        )
    }

    private func resize(_ panel: NSPanel, to size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let notch = Self.notch(for: screen)
        guard notch.hasNotch else { return hide() }

        let placed = HUDPlacement.frame(
            contentWidth: size.width,
            contentHeight: size.height,
            notch: notch,
            screenTopY: screen.frame.maxY
        )
        panel.setFrame(
            NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height),
            display: true
        )
        // A borderless panel's shadow lags a size change without this.
        panel.invalidateShadow()
    }

    deinit {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }
}
