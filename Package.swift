// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Zipic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TuyaCore", targets: ["TuyaCore"]),
        .executable(name: "Zipic", targets: ["Zipic"])
    ],
    targets: [
        .target(
            name: "TuyaCore",
            path: "Sources/TuyaCore"
        ),
        .executableTarget(
            name: "Zipic",
            dependencies: ["TuyaCore"],
            path: "Sources/Zipic"
        ),
        .testTarget(
            name: "ZipicTests",
            dependencies: ["TuyaCore"],
            path: "Tests/ZipicTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
