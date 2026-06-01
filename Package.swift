// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortWatch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortWatchCore", targets: ["PortWatchCore"]),
        .executable(name: "PortWatch", targets: ["PortWatch"])
    ],
    targets: [
        .target(name: "PortWatchCore"),
        .executableTarget(
            name: "PortWatch",
            dependencies: ["PortWatchCore"],
            path: "Sources/PortWatch"
        ),
        .testTarget(
            name: "PortWatchCoreTests",
            dependencies: ["PortWatchCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
