import Foundation

/// Which provider Hoot should use, and what it's allowed to see.
public struct AISettings: Codable, Equatable {
    public enum ProviderKind: String, Codable, CaseIterable {
        /// Filename rules only. Always available, never uses a model.
        case rulesOnly
        /// Apple's on-device model. Private and offline.
        case appleOnDevice
    }

    public init(
        provider: ProviderKind,
        allowLocalContentReading: Bool,
        renameMeaninglessFiles: Bool
    ) {
        self.provider = provider
        self.allowLocalContentReading = allowLocalContentReading
        self.renameMeaninglessFiles = renameMeaninglessFiles
    }

    public var provider: ProviderKind
    /// Whether a *local* provider may read a short excerpt from files.
    /// Has no effect on external providers, which never receive content.
    public var allowLocalContentReading: Bool
    /// Whether Hoot may propose a new name for a file whose current one says
    /// nothing. Depends on content reading: a name can only come from what is
    /// inside the file, never from the name that already failed.
    public var renameMeaninglessFiles: Bool

    public static let `default` = AISettings(
        // On-device inference is private and offline, so there's no
        // data-sharing tradeoff in preferring it when the Mac supports it.
        provider: .appleOnDevice,
        allowLocalContentReading: true,
        // Off by default. Renaming is the one thing Hoot does that changes
        // something the user typed, so it is asked for rather than assumed.
        renameMeaninglessFiles: false
    )

    private static let storageKey = "ai.settings"

    public static func load(from defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AISettings.self, from: data)
        else { return .default }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case provider, allowLocalContentReading, renameMeaninglessFiles
    }

    /// Decoded by hand so that adding a setting cannot silently reset the
    /// ones already stored. Synthesized decoding throws on a missing key,
    /// `load` falls back to `.default`, and the user's provider choice
    /// quietly reverts on the first launch after an update — a bug that
    /// would look like Hoot forgetting its settings for no reason.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(ProviderKind.self, forKey: .provider)
            ?? Self.default.provider
        allowLocalContentReading = try container.decodeIfPresent(
            Bool.self, forKey: .allowLocalContentReading
        ) ?? Self.default.allowLocalContentReading
        renameMeaninglessFiles = try container.decodeIfPresent(
            Bool.self, forKey: .renameMeaninglessFiles
        ) ?? Self.default.renameMeaninglessFiles
    }
}
