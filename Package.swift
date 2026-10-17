// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Shots",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "Shots",
            targets: ["Shots"]
        ),
        .executable(
            name: "Impact",
            targets: ["Impact"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Shots",
            dependencies: [],
            path: "Sources/Shots"
        ),
        .executableTarget(
            name: "Impact",
            dependencies: [],
            path: "Sources/Impact",
            exclude: ["audit.md"]
        )
    ]
)
