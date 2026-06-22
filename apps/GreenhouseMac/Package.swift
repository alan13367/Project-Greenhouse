// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GreenhouseMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GreenhouseCore", targets: ["GreenhouseCore"]),
        .executable(name: "GreenhouseMac", targets: ["GreenhouseMac"])
    ],
    targets: [
        .target(
            name: "GreenhouseCore",
            path: "Sources/GreenhouseCore"
        ),
        .executableTarget(
            name: "GreenhouseMac",
            dependencies: ["GreenhouseCore"],
            path: "Sources/GreenhouseMac"
        ),
        .testTarget(
            name: "GreenhouseCoreTests",
            dependencies: ["GreenhouseCore"],
            path: "Tests/GreenhouseCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
