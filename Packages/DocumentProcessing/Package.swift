// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentProcessing",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "DocumentProcessing", targets: ["DocumentProcessing"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain")
    ],
    targets: [
        .target(
            name: "DocumentProcessing",
            dependencies: ["WatakeDomain"]
        ),
        .testTarget(
            name: "DocumentProcessingTests",
            dependencies: ["DocumentProcessing", "WatakeDomain"]
        )
    ]
)
