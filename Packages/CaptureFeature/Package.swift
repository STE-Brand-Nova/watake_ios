// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CaptureFeature", targets: ["CaptureFeature"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "CaptureFeature",
            dependencies: [
                "WatakeDomain",
                "DesignSystem"
            ]
        ),
        .testTarget(
            name: "CaptureFeatureTests",
            dependencies: [
                "CaptureFeature",
                "WatakeDomain",
                "DesignSystem"
            ]
        )
    ]
)
