import XCTest
@testable import HootKit

/// Guards the rule ADR-0001 sets out: the engine depends on nothing.
///
/// This is checked as a test rather than trusted to discipline, because the
/// failure it prevents is silent on macOS — a stray `import PDFKit` compiles
/// perfectly here and only surfaces when someone tries to build for Windows,
/// long after the person who added it has moved on.
final class DependencyRuleTests: XCTestCase {

    /// Frameworks that exist only on Apple platforms. Any of them inside the
    /// engine makes a Windows build impossible.
    private static let forbidden = [
        "AppKit", "UIKit", "SwiftUI", "PDFKit", "Vision", "FoundationModels",
        "ImageIO", "CoreGraphics", "UserNotifications", "UniformTypeIdentifiers",
        "Compression", "CoreServices", "Quartz", "AVFoundation"
    ]

    func testEngineImportsNoPlatformFramework() throws {
        let engine = Self.engineDirectory()
        let files = try Self.swiftFiles(under: engine)

        XCTAssertFalse(files.isEmpty, "found no engine sources to check at \(engine.path)")

        var offences: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed
                    .dropFirst("import ".count)
                    .trimmingCharacters(in: .whitespaces)
                if Self.forbidden.contains(module) {
                    offences.append("\(file.lastPathComponent) imports \(module)")
                }
            }
        }

        XCTAssertTrue(
            offences.isEmpty,
            """
            The engine must depend on nothing platform-specific (ADR-0001).
            Move the code behind a protocol in Platform/PlatformCapabilities.swift
            and put the framework call in a platform target instead:
            \(offences.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Locating sources

    private static func engineDirectory() -> URL {
        // Tests/HootKitTests/ThisFile.swift -> package root -> Sources/HootKit
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/HootKit")
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
