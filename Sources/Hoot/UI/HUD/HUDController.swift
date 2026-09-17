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

    /// Set while something is happening that the pointer leaving must not
    /// interrupt. A drag out of the panel is the case that needs it: the
    /// first thing such a drag does is leave, which would otherwise collapse
    /// the window from 420 to 190 and pull the drag source out from under
    /// the session.
    private var isHoldingOpen = false
    /// Watches for the mouse coming up, which is the only signal that a drag
    /// has finished — SwiftUI's `.onDrag` reports a start and never an end.
    private var dragMonitors: [Any] = []
    /// A backstop. If a mouse-up is somehow missed, a panel held open for
    /// ever is a worse failure than one that closes a moment early.
    private var holdTimeout: Task<Void, Never>?

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
        // Read whatever is on the shelf now, rather than waiting for a
        // folder to change.
        Task { await appState.refreshShelf(force: true) }
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
        // One subscription, to the thing the panel draws. The HUD used to
        // watch the plan and the walk built from it; it no longer has an
        // opinion about either, which is the whole point of the change.
        appState.$shelf
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
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

        // Opening is the moment the folder is worth reading again. Off the
        // main run-loop turn for the same family of reasons the frame resize
        // is: this is called from inside a SwiftUI update.
        if open, let appState {
            Task { await appState.refreshShelf() }
        }
    }

    private func syncHotKeys() {
        guard isEnabled, isPanelOpen else { return hotKeys.unregister() }
        hotKeys.register { [weak self] page in
            guard let appState = self?.appState else { return }
            switch page {
            case .previous: appState.showPreviousShelfFolder()
            case .next: appState.showNextShelfFolder()
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

        // The panel holds a scrolling list now. This used to swallow every
        // scroll event over it — "the panel is not a scrollable surface" —
        // which would leave the list unable to scroll.
        guard SwipeTracker.isHorizontal(deltaX: event.scrollingDeltaX,
                                        deltaY: event.scrollingDeltaY)
        else { return event }

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
        case .next: appState.showNextShelfFolder()
        case .previous: appState.showPreviousShelfFolder()
        }
        return nil
    }

    // MARK: - What to show

    /// The panel is shown whenever the HUD is switched on.
    ///
    /// It used to be conditional on a non-idle walk existing, so a folder
    /// with nothing waiting left nothing at the notch to point at — reported
    /// as "pointing at the camera still doesn't open the notch", and it was
    /// this line. A shelf has something to say about an empty folder too.
    func refresh() {
        guard isEnabled, let appState else { return hide() }
        show(appState: appState)
    }

    private func show(appState: AppState) {
        let view = HUDView(
            shelf: appState.shelf,
            isOpen: Binding(
                get: { [weak self] in self?.isPanelOpen ?? false },
                set: { [weak self] in self?.setPanelOpen($0) }
            ),
            notch: Self.notch(for: NSScreen.main),
            isHoldingOpen: isHoldingOpen,
            untidy: appState.shelf.current.map { appState.untidyCount(in: $0.url) } ?? 0,
            now: Date(),
            onShowFolder: { appState.showShelfFolder(at: $0) },
            onSelect: { appState.selectShelfEntry($0) },
            onCycleSort: { appState.cycleShelfSort() },
            onReveal: { appState.revealInFinder() },
            onTidy: { appState.openReviewForTidying() },
            onPreview: { [weak self] url in self?.preview(url) },
            onDragStart: { [weak self] in self?.beginHold() },
            onRevealEntry: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
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

    // MARK: - Looking inside a file, and carrying one out

    /// Quick Look, the same panel the Finder opens on space.
    ///
    /// The activation is not optional. Hoot is an accessory app and this
    /// panel is non-activating, so at the moment of the hold Hoot is not the
    /// active application — and a Quick Look panel ordered front from an
    /// inactive app never becomes key. Space and the arrow keys would do
    /// nothing, and it could sit behind whatever is in front.
    ///
    /// The consequence is deliberate and worth stating: **previewing takes
    /// focus.** It happens in response to a held click, never to a hover, so
    /// pointing at the notch mid-sentence still costs nothing.
    private func preview(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        QuickLookPanel.shared.show(url)
    }

    /// Holds the panel open across a drag.
    ///
    /// The first thing a drag out of the panel does is take the pointer off
    /// it, and `HUDView.onHover` would close it — resizing the window from
    /// 420 to 190 and pulling the drag source out from under the session
    /// before it had travelled a pixel.
    private func beginHold() {
        guard !isHoldingOpen else { return }
        isHoldingOpen = true
        refresh()

        // Both monitors, because a drag can end anywhere: a global one sees
        // the mouse come up over the Finder, a local one sees it come up
        // back over the panel it started from.
        let finish: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.endHold() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: finish) {
            dragMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { event in
            finish(event)
            return event
        }) {
            dragMonitors.append(local)
        }

        holdTimeout?.cancel()
        holdTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.endHold()
        }
    }

    private func endHold() {
        guard isHoldingOpen else { return }
        isHoldingOpen = false
        holdTimeout?.cancel()
        holdTimeout = nil
        dragMonitors.forEach(NSEvent.removeMonitor)
        dragMonitors.removeAll()
        refresh()
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
        dragMonitors.forEach(NSEvent.removeMonitor)
        holdTimeout?.cancel()
    }
}
