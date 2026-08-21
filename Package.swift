// swift-tools-version: 5.9
import PackageDescription

// Hoot is split so the rules that decide where a file belongs can run anywhere,
// while the frameworks that read files and draw windows stay at the edge.
// See docs/decisions/0001-engine-and-platform-adapters.md.
let package = Package(
    name: "Hoot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The engine is a library in its own right: a Windows app, a CLI or a
        // test harness links it without dragging in any Apple framework.
        .library(name: "HootKit", targets: ["HootKit"]),
        .library(name: "HootPlatformMac", targets: ["HootPlatformMac"])
    ],
    targets: [
        // THE ENGINE. Foundation only — no AppKit, SwiftUI, PDFKit, Vision,
        // FoundationModels or Compression. What it needs from a platform it
        // declares as a protocol in Platform/PlatformCapabilities.swift.
        .target(
            name: "HootKit",
            path: "Sources/HootKit"
        ),

        // APPLE ADAPTERS. The only target allowed to import Apple frameworks
        // that a Windows build could not satisfy.
        .target(
            name: "HootPlatformMac",
            dependencies: ["HootKit"],
            path: "Sources/HootPlatformMac"
        ),

        // THE macOS APP. Wires the Apple adapters into the engine and draws
        // the interface.
        .executableTarget(
            name: "Hoot",
            dependencies: ["HootKit", "HootPlatformMac"],
            path: "Sources/Hoot",
            resources: [
                .process("Resources")
            ]
        ),

        // The behaviour and safety checks, built as a real target so they
        // link the shipping modules rather than a recompiled copy.
        .executableTarget(
            name: "Verification",
            dependencies: ["HootKit", "HootPlatformMac"],
            path: "Verification",
            exclude: ["run.sh"]
        ),

        // Guards the dependency rule the ADR sets out, so a stray import
        // fails the build rather than the Windows port.
        .testTarget(
            name: "HootKitTests",
            dependencies: ["HootKit"],
            path: "Tests/HootKitTests"
        )
    ]
)
