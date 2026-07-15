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
        .library(name: "PokerBot", targets: ["PokerBot"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .target(name: "PokerSession", dependencies: ["PokerCore"]),
        .target(name: "PokerBot", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerCorePublicAPITests", dependencies: ["PokerCore"]),
        .testTarget(name: "PokerSessionTests", dependencies: ["PokerSession", "PokerCore"]),
        .testTarget(name: "PokerSessionPublicAPITests", dependencies: ["PokerSession", "PokerCore"]),
        .testTarget(name: "PokerBotTests", dependencies: ["PokerBot", "PokerCore"]),
        .testTarget(name: "PokerBotPublicAPITests", dependencies: ["PokerBot", "PokerCore"]),
    ]
)
