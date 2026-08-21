import Foundation

/// Finds files that are successive versions of the same thing.
///
/// Implements the "Old'nGray" idea from Bergman & Whittaker's work on
/// subjective importance: when several versions of a document sit side by
/// side, the user has to read every name to work out which one is current.
/// Graying out the superseded ones cut retrieval failures from 24% to 4% and
/// roughly halved retrieval time in their evaluation.
///
/// Hoot has a particular reason to care: its own collision-safe naming
/// creates files like "report 2.pdf", so it manufactures exactly the version
/// clutter this addresses.
public struct VersionFamilies {
    public init() {}


    public struct Family {
        /// The version that should stay in plain sight.
        public let current: FileItem
        /// Superseded versions, to be demoted rather than deleted.
        public let superseded: [FileItem]
    }

    /// Version markers appended to an otherwise identical name.
    private static let versionPatterns = [
        #"\s*\(\d+\)$"#,          // "report (2)"
        #"\s+\d+$"#,              // "report 2"        (Hoot's own collision suffix)
        #"[\s._-]*v\d+$"#,        // "report-v2", "report_v3"
        #"[\s._-]*copy(\s*\d+)?$"#,
        #"[\s._-]*(final|draft|latest|new|old|rev|revised)$"#
    ]

    /// Groups files into version families. Files with no siblings are omitted.
    public func families(in files: [FileItem]) -> [Family] {
        var byKey: [String: [FileItem]] = [:]
        for file in files {
            byKey[Self.familyKey(for: file), default: []].append(file)
        }

        return byKey.values.compactMap { members in
            guard members.count > 1 else { return nil }

            // Newest wins. Where dates tie, the higher explicit version number
            // does — "report 3" supersedes "report 2" even if copied together.
            let ordered = members.sorted { lhs, rhs in
                let lhsDate = lhs.modifiedAt ?? .distantPast
                let rhsDate = rhs.modifiedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return Self.versionNumber(in: lhs.filename) > Self.versionNumber(in: rhs.filename)
            }
            return Family(current: ordered[0], superseded: Array(ordered.dropFirst()))
        }
    }

    /// Two files belong to the same family when their names match once version
    /// markers are removed — and only if the extension matches too, so a PDF
    /// export is never treated as a version of the document it came from.
    public static func familyKey(for file: FileItem) -> String {
        var base = (file.filename as NSString).deletingPathExtension.lowercased()

        // Strip repeatedly: "report final v2" -> "report".
        var changed = true
        while changed {
            changed = false
            for pattern in versionPatterns {
                let stripped = base.replacingOccurrences(
                    of: pattern, with: "", options: [.regularExpression]
                )
                if stripped != base, !stripped.trimmingCharacters(in: .whitespaces).isEmpty {
                    base = stripped
                    changed = true
                }
            }
        }

        base = base.trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
        return "\(base)|\(file.fileExtension.lowercased())"
    }

    private static func versionNumber(in filename: String) -> Int {
        let base = (filename as NSString).deletingPathExtension
        guard let match = base.range(of: #"\d+$"#, options: .regularExpression) else { return 0 }
        return Int(base[match]) ?? 0
    }
}
