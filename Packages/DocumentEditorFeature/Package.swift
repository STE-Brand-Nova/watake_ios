// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentEditorFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DocumentEditorFeature", targets: ["DocumentEditorFeature"])],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(name: "DocumentEditorFeature", dependencies: ["WatakeDomain", "DesignSystem"]),
        .testTarget(name: "DocumentEditorFeatureTests", dependencies: ["DocumentEditorFeature", "WatakeDomain"])
    ]
)
