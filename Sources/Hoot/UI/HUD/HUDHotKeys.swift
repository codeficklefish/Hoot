import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts for paging the HUD.
///
/// The panel never takes keyboard focus — that is exactly why it can be
/// pointed at mid-sentence without disturbing anything — so a key press never
/// reaches it the ordinary way. Keystrokes go to the frontmost application's
/// key window, and Hoot is never frontmost. A local event monitor does not
/// help either: it only sees what was already delivered to this app.
///
/// A registered hot key is the one route that asks for none of that. The
/// system matches the combination before the event is delivered anywhere,
/// hands it straight here, and no other app sees it — with no Accessibility
/// or Input Monitoring permission, because nothing is being monitored.
///
/// Why not the bare arrow keys: a hot key is global by nature, and taking
/// ← and → system-wide would break every list and text field on the Mac.
/// The modifiers are what make the shortcut ours rather than everyone's.
///
/// Registered only while the panel is open, so ⌃⌥← and ⌃⌥→ belong to
/// whatever the person is working in for all the time it is not.
@MainActor
final class HUDHotKeys {

    enum Page: UInt32 {
        case previous = 1
        case next = 2
    }

    /// Shown to the user, and the single source for what is registered below.
    static let shortcutDescription = "⌃⌥← / ⌃⌥→"

    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var onPage: ((Page) -> Void)?

    /// `'hoot'`, so the ids below cannot collide with another application's.
    private static let signature: OSType = 0x686F_6F74

    var isRegistered: Bool { handler != nil }

    func register(onPage: @escaping (Page) -> Void) {
        guard handler == nil else { return }
        self.onPage = onPage

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard read == noErr, let page = Page(rawValue: id.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                // Carbon delivers hot keys on the main run loop, which is the
                // only thread this class is ever touched from.
                MainActor.assumeIsolated {
                    Unmanaged<HUDHotKeys>.fromOpaque(context)
                        .takeUnretainedValue()
                        .onPage?(page)
                }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            // Nothing to recover: the swipe and the pips still page the walk,
            // and a shortcut that failed to register is worth knowing about
            // without being worth interrupting anyone over.
            NSLog("Hoot: couldn't install the HUD's hot key handler (\(status)).")
            handler = nil
            return
        }

        add(keyCode: UInt32(kVK_LeftArrow), as: .previous)
        add(keyCode: UInt32(kVK_RightArrow), as: .next)
    }

    func unregister() {
        for hotKey in registered { UnregisterEventHotKey(hotKey) }
        registered.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        onPage = nil
    }

    private func add(keyCode: UInt32, as page: Page) {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: Self.signature, id: page.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        // Another app may already own the combination. That is its right, and
        // the HUD is still fully usable by swipe and by pip.
        guard status == noErr, let reference else {
            NSLog("Hoot: \(Self.shortcutDescription) is already taken (\(status)).")
            return
        }
        registered.append(reference)
    }

    deinit {
        for hotKey in registered { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
