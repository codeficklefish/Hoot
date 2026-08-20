import Foundation

/// Which provider Hoot should use, and what it's allowed to see.
struct AISettings: Codable, Equatable {
    enum ProviderKind: String, Codable, CaseIterable {
        /// Filename rules only. Always available, never uses a model.
        case rulesOnly
        /// Apple's on-device model. Private and offline.
        case appleOnDevice
    }

    var provider: ProviderKind
    /// Whether a *local* provider may read a short excerpt from files.
    /// Has no effect on external providers, which never receive content.
    var allowLocalContentReading: Bool

    static let `default` = AISettings(
        // On-device inference is private and offline, so there's no
        // data-sharing tradeoff in preferring it when the Mac supports it.
        provider: .appleOnDevice,
        allowLocalContentReading: true
    )

    private static let storageKey = "ai.settings"

    static func load(from defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AISettings.self, from: data)
        else { return .default }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
