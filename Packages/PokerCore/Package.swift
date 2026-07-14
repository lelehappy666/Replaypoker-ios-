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
        .library(name: "PokerSession", targets: ["PokerSession"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .target(name: "PokerSession", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCorePublicAPITests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerSessionTests", dependencies: ["PokerSession", "PokerCore"]),
        .testTarget(name: "PokerSessionPublicAPITests", dependencies: ["PokerSession", "PokerCore"]),
    ]
)
