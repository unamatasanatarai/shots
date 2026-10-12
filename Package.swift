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
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Shots",
            dependencies: [],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ShotsTests",
            dependencies: ["Shots"],
            path: "Tests/AppTests"
        )
    ]
)
