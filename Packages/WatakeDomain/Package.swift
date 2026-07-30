// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatakeDomain",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WatakeDomain", targets: ["WatakeDomain"])
    ],
    targets: [
        .target(name: "WatakeDomain"),
        .testTarget(
            name: "WatakeDomainTests",
            dependencies: ["WatakeDomain"]
        )
    ]
)
