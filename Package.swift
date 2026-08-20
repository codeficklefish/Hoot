// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hoot",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Hoot",
            path: "Sources/Hoot",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
