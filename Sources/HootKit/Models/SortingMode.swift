import Foundation

/// How much interpretation the user wants Hoot to do.
///
/// Working out what a file is *about* is the interesting thing Hoot does, but
/// it is not what everybody wants. Sorting a Downloads folder into
/// Screenshots, Images and Installers is a smaller promise, and for a lot of
/// people it is the whole job — no model, no waiting, and a result they can
/// predict before they press Review.
///
/// So the two modes are not settings of the same machine at different
/// strengths. They are different answers to "what should the folders be
/// named after": the subject, or the file.
public enum SortingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Folders named after subjects — a trip, a thesis, finance. Reads inside
    /// files and uses the on-device model.
    case byMeaning
    /// Folders named after file types — Screenshots, Images, Spreadsheets.
    /// Decided from the filename and extension alone.
    case byType

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .byMeaning: return "By meaning"
        case .byType: return "By type"
        }
    }

    /// One line, in the UI, next to the choice.
    public var summary: String {
        switch self {
        case .byMeaning:
            return "Folders named after what files are about — a trip, a thesis, finance."
        case .byType:
            return "Folders named after what files are — Screenshots, Images, Spreadsheets."
        }
    }

    /// The consequence the user is actually choosing between, said plainly.
    public var tradeoff: String {
        switch self {
        case .byMeaning:
            return "Reads inside files and takes a few seconds. Best when names say nothing."
        case .byType:
            return "Instant, and never opens a file. Nothing is read and no model runs."
        }
    }

    public var symbolName: String {
        switch self {
        case .byMeaning: return "sparkles"
        case .byType: return "square.grid.2x2"
        }
    }

    /// True when this mode reaches the on-device model at all. The privacy
    /// text in Settings depends on this, so it is stated here once rather
    /// than re-derived at each place that asks.
    public var usesModel: Bool { self == .byMeaning }

    // MARK: - Persistence

    private static let storageKey = "sorting.mode"

    public static func load(from defaults: UserDefaults = .standard) -> SortingMode {
        guard let raw = defaults.string(forKey: storageKey),
              let mode = SortingMode(rawValue: raw)
        else { return .byMeaning }
        return mode
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}
