// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentSearchFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DocumentSearchFeature", targets: ["DocumentSearchFeature"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain")
    ],
    targets: [
        .target(name: "DocumentSearchFeature", dependencies: ["WatakeDomain"]),
        .testTarget(name: "DocumentSearchFeatureTests", dependencies: ["DocumentSearchFeature", "WatakeDomain"])
    ]
)
