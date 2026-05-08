// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoltHIDPP",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BoltHIDPP", targets: ["BoltHIDPP"]),
        .executable(name: "bolt-battery-swift", targets: ["bolt-battery-swift"]),
    ],
    targets: [
        .target(name: "BoltHIDPP"),
        .executableTarget(
            name: "bolt-battery-swift",
            dependencies: ["BoltHIDPP"]
        ),
        .testTarget(
            name: "BoltHIDPPTests",
            dependencies: ["BoltHIDPP"]
        ),
    ]
)
