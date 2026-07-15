import Foundation
import PokerBot
import PokerCore
import Testing

@Test func 普通导入只能使用安全机器人接口() throws {
    #expect(BotSettings.recommended.model == .balanced)
    _ = BotDecisionEngine()
    _ = BotDecisionService()
    _ = BotHistorySummary(
        sampleCount: 0,
        opponentFoldBasisPoints: 0,
        opponentAggressionBasisPoints: 0
    )

    for probe in HiddenInformationProbe.allCases {
        try expectTypecheckFailure(probe)
    }
}

private enum HiddenInformationProbe: String, CaseIterable {
    case deck = "_ = botObservation.deck"
    case seed = "_ = botObservation.seed"
    case opponentCards = "_ = botObservation.opponentHoleCards"
    case checkpoint = "let _: HoldemCheckpoint.Type = HoldemCheckpoint.self"
    case explicitSeed = "_ = try BotObservation(handID: \"hand\", stateVersion: 0, config: config, observation: playerObservation, seed: 7)"
    case historyHoleCards = "_ = historySummary.holeCards"
}

private func expectTypecheckFailure(_ probe: HiddenInformationProbe) throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = try botModulesDirectory(in: packageRoot)
    let source = """
    import PokerBot
    import PokerCore

    func unavailableObservation() -> BotObservation { fatalError() }
    func unavailablePlayerObservation() -> PlayerObservation { fatalError() }
    let botObservation = unavailableObservation()
    let playerObservation = unavailablePlayerObservation()
    let historySummary = BotHistorySummary(
        sampleCount: 1,
        opponentFoldBasisPoints: 0,
        opponentAggressionBasisPoints: 0
    )
    let config = try HandConfig(
        smallBlind: try Chips(10),
        bigBlind: try Chips(20),
        dealer: try SeatID(0)
    )
    \(probe.rawValue)
    """
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("poker-bot-boundary-\(UUID().uuidString).swift")
    try source.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["swiftc", "-typecheck", "-I", modules.path, file.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let diagnostics = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    #expect(process.terminationStatus == 1, Comment(rawValue: diagnostics))
    #expect(diagnostics.contains("no such module") == false, Comment(rawValue: diagnostics))
    #expect(
        diagnostics.contains("has no member")
            || diagnostics.contains("cannot find")
            || diagnostics.contains("extra argument"),
        Comment(rawValue: diagnostics)
    )
}

private func botModulesDirectory(in packageRoot: URL) throws -> URL {
    let build = packageRoot.appendingPathComponent(".build", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: build,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    while let candidate = enumerator?.nextObject() as? URL {
        let modules = candidate.deletingLastPathComponent()
        if candidate.lastPathComponent == "PokerBot.swiftmodule",
           modules.lastPathComponent == "Modules" {
            return modules
        }
    }
    throw PublicBoundaryError.modulesNotFound
}

private enum PublicBoundaryError: Error {
    case modulesNotFound
}
