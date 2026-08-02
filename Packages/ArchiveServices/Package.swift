// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArchiveServices",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ArchiveServices", targets: ["ArchiveServices"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain"),
        .package(path: "../WatakeStorage")
    ],
    targets: [
        .target(name: "ArchiveServices", dependencies: ["WatakeDomain"]),
        .testTarget(name: "ArchiveServicesTests", dependencies: ["ArchiveServices", "WatakeDomain", "WatakeStorage"])
    ]
)
