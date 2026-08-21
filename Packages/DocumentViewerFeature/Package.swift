// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentViewerFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DocumentViewerFeature", targets: ["DocumentViewerFeature"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../DesignSystem"),
        .package(path: "../DocumentProcessing"),
        .package(path: "../WatermarkEditorFeature")
    ],
    targets: [
        .target(
            name: "DocumentViewerFeature",
            dependencies: ["WatakeDomain", "DesignSystem", "DocumentProcessing", "WatermarkEditorFeature"]
        ),
        .testTarget(name: "DocumentViewerFeatureTests", dependencies: ["DocumentViewerFeature", "WatakeDomain"])
    ]
)
