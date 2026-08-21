import Foundation

/// Remembers the times the user overruled Hoot.
///
/// A correction is the most valuable signal available: unlike a folder scan,
/// which shows where files ended up, this records a case where Hoot was
/// specifically wrong and what the right answer was. Those examples are fed
/// back into the personal model, so the same mistake stops recurring.
///
/// This is also what keeps organizing an *active* act rather than a passive
/// one — the correction the user makes by hand is the thing that teaches.
public struct CorrectionLog: Codable {
    public init() {}


    public struct Correction: Codable, Equatable {
        /// The words describing the file, in the same form the classifier uses.
        public let features: [String]
        /// Where the user actually wanted it.
        public let chosenFolder: String
        /// What Hoot had proposed, kept for display.
        public let rejectedFolder: String
        public let madeAt: Date
    }

    public private(set) var corrections: [Correction] = []

    /// Corrections are weighted more heavily than passive examples by being
    /// repeated when training — being told directly is worth more than being
    /// inferred, but not so much that one correction overwhelms everything.
    public static let trainingWeight = 3

    private static let maximumCorrections = 500

    public var isEmpty: Bool { corrections.isEmpty }
    public var count: Int { corrections.count }

    public mutating func record(features: [String], chose: String, insteadOf rejected: String) {
        guard chose.lowercased() != rejected.lowercased() else { return }

        // One correction per file's vocabulary; a later change of mind replaces
        // an earlier one rather than arguing with it.
        corrections.removeAll { $0.features == features }
        corrections.insert(
            Correction(features: features, chosenFolder: chose,
                       rejectedFolder: rejected, madeAt: Date()),
            at: 0
        )
        if corrections.count > Self.maximumCorrections {
            corrections = Array(corrections.prefix(Self.maximumCorrections))
        }
    }

    public mutating func removeAll() {
        corrections.removeAll()
    }

    /// Training samples, with corrections repeated so they carry more weight
    /// than a file that merely happens to sit somewhere.
    public var trainingSamples: [LearnedClassifier.Sample] {
        corrections.flatMap { correction in
            Array(
                repeating: LearnedClassifier.Sample(
                    features: correction.features, folder: correction.chosenFolder
                ),
                count: Self.trainingWeight
            )
        }
    }

    // MARK: - Persistence

    private static func storeURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        let folder = base.appending(path: "Hoot", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return folder.appending(path: "corrections.json")
    }

    public static func load(from url: URL? = nil) -> CorrectionLog {
        let target = url ?? storeURL()
        guard let data = try? Data(contentsOf: target),
              let decoded = try? JSONDecoder().decode(CorrectionLog.self, from: data)
        else { return CorrectionLog() }
        return decoded
    }

    public func save(to url: URL? = nil) {
        let target = url ?? Self.storeURL()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: target, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}
