// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SumSnap",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SumKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SumSnap",
            dependencies: ["SumKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SumKitTests",
            dependencies: ["SumKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
