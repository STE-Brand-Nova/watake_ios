// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatermarkEditorFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WatermarkEditorFeature", targets: ["WatermarkEditorFeature"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "WatermarkEditorFeature",
            dependencies: ["WatakeDomain", "DesignSystem"]
        ),
        .testTarget(
            name: "WatermarkEditorFeatureTests",
            dependencies: ["WatermarkEditorFeature", "WatakeDomain"]
        )
    ]
)
