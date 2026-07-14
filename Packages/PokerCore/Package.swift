// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PokerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
    ],
    products: [
        .library(name: "PokerCore", targets: ["PokerCore"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCorePublicAPITests", dependencies: ["PokerCore"]),
    ]
)
