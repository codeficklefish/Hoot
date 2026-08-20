import Foundation

/// Remembers the folder names the user prefers.
///
/// Hoot's suggestions are generated fresh each run, so without this the same
/// correction has to be made every time — rename "Software Development" to
/// "Books" today, and the same three e-books get the same wrong folder
/// tomorrow. Recording the correction makes the app converge on the user's
/// own vocabulary instead of the model's.
struct FolderPreferences: Codable, Equatable {
    /// Proposed name (lowercased) -> the name the user actually wants.
    private var mappings: [String: String]

    init(mappings: [String: String] = [:]) {
        self.mappings = mappings
    }

    var isEmpty: Bool { mappings.isEmpty }

    /// Learned pairs, ordered for display.
    var entries: [(proposed: String, preferred: String)] {
        mappings
            .sorted { $0.key < $1.key }
            .map { (proposed: $0.key, preferred: $0.value) }
    }

    /// The user's preferred name for a suggestion, or the suggestion itself.
    func preferredName(for proposed: String) -> String {
        mappings[proposed.lowercased()] ?? proposed
    }

    /// Records that `proposed` should have been `preferred`.
    mutating func remember(proposed: String, preferred: String) {
        let key = proposed.lowercased()

        // Renaming something back to itself isn't a preference worth keeping.
        guard key != preferred.lowercased() else {
            mappings.removeValue(forKey: key)
            return
        }

        mappings[key] = preferred

        // If the user previously mapped A->B and now renames B->C, the old
        // rule would send files to a name they've since rejected.
        for (existingKey, existingValue) in mappings
        where existingValue.lowercased() == key && existingKey != key {
            mappings[existingKey] = preferred
        }
    }

    mutating func forget(proposed: String) {
        mappings.removeValue(forKey: proposed.lowercased())
    }

    mutating func removeAll() {
        mappings.removeAll()
    }

    // MARK: - Persistence

    private static let storageKey = "folder.preferences"

    static func load(from defaults: UserDefaults = .standard) -> FolderPreferences {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(FolderPreferences.self, from: data)
        else { return FolderPreferences() }
        return decoded
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
