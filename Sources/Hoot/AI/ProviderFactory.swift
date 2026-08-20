import Foundation

/// Builds the provider matching the user's settings. This is the only place
/// that knows which concrete providers exist, so adding Ollama or an
/// OpenAI-compatible provider later means touching one function.
enum ProviderFactory {
    static func makeProvider(for settings: AISettings) -> AIProvider? {
        switch settings.provider {
        case .rulesOnly:
            return nil
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return AppleOnDeviceProvider()
            }
            #endif
            return nil
        }
    }

    /// Whether this build can offer on-device intelligence at all, regardless
    /// of the user's current selection.
    static var supportsAppleOnDevice: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}
