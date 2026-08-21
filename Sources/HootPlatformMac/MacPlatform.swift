import Foundation
import HootKit

/// Everything the engine needs from macOS, assembled in one place.
///
/// The engine states its requirements as protocols and never names a framework
/// (ADR-0001). This is where those requirements are answered for Apple
/// platforms — and it is the file a Windows port would sit beside, not edit.
public enum MacPlatform {

    /// The engine's own decoder, not Apple's.
    ///
    /// It is byte-identical to the system one on real archives and costs about
    /// two milliseconds per megabyte, so there is no reason to run different
    /// code on each platform — and every reason not to: this way macOS
    /// exercises the same path Windows will.
    public static func makeInflater() -> ArchiveInflating {
        Inflate()
    }

    public static func makeTextExtractor() -> TextExtracting {
        TextExtractor()
    }

    public static func makeFileWatcher() -> FileWatching {
        FileWatcher()
    }

    @MainActor
    public static func makeNotifier() -> Notifying {
        NotificationService()
    }

    /// The on-device model, when this Mac can run it.
    ///
    /// Returns nil rather than a stand-in: the caller already falls back to
    /// filename rules, and a fake provider would hide the fact that the real
    /// one is unavailable.
    public static func makeAIProvider(for settings: AISettings) -> AIProvider? {
        switch settings.provider {
        case .rulesOnly:
            return nil
        case .appleOnDevice:
            if #available(macOS 26.0, *) {
                return AppleOnDeviceProvider()
            }
            return nil
        }
    }

    /// Whether this build can offer on-device intelligence at all, regardless
    /// of what the user has selected.
    public static var supportsOnDeviceAI: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
