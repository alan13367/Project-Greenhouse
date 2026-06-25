// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GreenhouseMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GreenhouseCore", targets: ["GreenhouseCore"]),
        .library(name: "GreenhouseRuntime", targets: ["GreenhouseRuntime"]),
        .executable(name: "GreenhouseMac", targets: ["GreenhouseMac"]),
        .executable(
            name: "GreenhouseRuntimeProbe",
            targets: ["GreenhouseRuntimeProbe"]
        )
    ],
    targets: [
        .target(
            name: "GreenhouseCore",
            path: "Sources/GreenhouseCore"
        ),
        .target(
            name: "GreenhouseRuntime",
            dependencies: ["GreenhouseCore"],
            path: "Sources/GreenhouseRuntime"
        ),
        .executableTarget(
            name: "GreenhouseMac",
            dependencies: ["GreenhouseCore", "GreenhouseRuntime"],
            path: "Sources/GreenhouseMac"
        ),
        .executableTarget(
            name: "GreenhouseRuntimeProbe",
            dependencies: ["GreenhouseCore", "GreenhouseRuntime"],
            path: "Sources/GreenhouseRuntimeProbe"
        ),
        .testTarget(
            name: "GreenhouseCoreTests",
            dependencies: ["GreenhouseCore"],
            path: "Tests/GreenhouseCoreTests"
        ),
        .testTarget(
            name: "GreenhouseRuntimeTests",
            dependencies: ["GreenhouseCore", "GreenhouseRuntime"],
            path: "Tests/GreenhouseRuntimeTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
