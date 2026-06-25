// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Atlas",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "Atlas", targets: ["Atlas"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Atlas",
            path: "Sources/Atlas",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
