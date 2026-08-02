// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureServices",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CaptureServices", targets: ["CaptureServices"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain")
    ],
    targets: [
        .target(
            name: "CaptureServices",
            dependencies: ["WatakeDomain"]
        ),
        .testTarget(
            name: "CaptureServicesTests",
            dependencies: ["CaptureServices", "WatakeDomain"]
        )
    ]
)
