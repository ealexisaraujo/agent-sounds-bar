// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentSoundsBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentSoundsBar",
            path: "Sources/AgentSoundsBar"
        ),
        .testTarget(
            name: "AgentSoundsBarTests",
            dependencies: ["AgentSoundsBar"],
            path: "tests/AgentSoundsBarTests"
        )
    ]
)
