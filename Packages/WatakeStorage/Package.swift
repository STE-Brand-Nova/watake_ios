// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatakeStorage",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WatakeStorage", targets: ["WatakeStorage"])
    ],
    dependencies: [
        .package(path: "../WatakeDomain")
    ],
    targets: [
        .target(
            name: "WatakeStorage",
            dependencies: ["WatakeDomain"]
        ),
        .testTarget(
            name: "WatakeStorageTests",
            dependencies: ["WatakeStorage", "WatakeDomain"]
        )
    ]
)
