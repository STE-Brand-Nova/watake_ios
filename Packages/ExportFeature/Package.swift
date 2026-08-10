// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExportFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ExportFeature", targets: ["ExportFeature"])],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(name: "ExportFeature", dependencies: ["WatakeDomain", "DesignSystem"]),
        .testTarget(name: "ExportFeatureTests", dependencies: ["ExportFeature", "WatakeDomain"])
    ]
)
