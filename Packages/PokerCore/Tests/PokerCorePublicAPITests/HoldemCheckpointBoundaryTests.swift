import Foundation
import Testing
import PokerCore

@Test func publicHoldemGameRemainsOpaqueAndNonCodable() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 81
    )

    #expect(Mirror(reflecting: game).children.isEmpty)
    try expectTypecheckFailure(
        "func requiresEncodable<T: Encodable>(_: T) {}\nrequiresEncodable(game)",
        named: "holdem-game-codable",
        expectedDiagnostic: "requires that 'HoldemGame' conform to 'Encodable'"
    )
}

@Test func packageCheckpointSymbolsAreUnavailableToOrdinaryImport() throws {
    try expectTypecheckFailure(
        "let _: HoldemCheckpoint.Type = HoldemCheckpoint.self",
        named: "checkpoint-type",
        expectedDiagnostic: "cannot find 'HoldemCheckpoint' in scope"
    )
    try expectTypecheckFailure(
        "_ = game.makeCheckpoint()",
        named: "checkpoint-export",
        expectedDiagnostic: "'makeCheckpoint' is inaccessible due to 'package' protection level"
    )
    try expectTypecheckFailure(
        "_ = HoldemGame.restore",
        named: "checkpoint-restore",
        expectedDiagnostic: "'restore' is inaccessible due to 'package' protection level"
    )
}

private func expectTypecheckFailure(
    _ expression: String,
    named name: String,
    expectedDiagnostic: String
) throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = packageRoot
        .appendingPathComponent(".build/arm64-apple-macosx/debug/Modules", isDirectory: true)
    let source = """
    import PokerCore

    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 82
    )
    \(expression)
    """
    let probe = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString).swift")
    try source.write(to: probe, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: probe) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "swiftc", "-typecheck",
        "-I", modules.path,
        probe.path,
    ]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()

    let diagnostics = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    #expect(process.terminationStatus == 1, Comment(rawValue: diagnostics))
    #expect(diagnostics.contains(expectedDiagnostic), Comment(rawValue: diagnostics))
    #expect(diagnostics.contains("no such module") == false, Comment(rawValue: diagnostics))
}
