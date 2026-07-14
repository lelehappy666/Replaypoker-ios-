import Foundation
import PokerCore
import PokerSession
import Testing

@Test func publicStoreExposesOnlySafeObservationsAndCompletedHistory() throws {
    let directory = try PublicTemporaryDirectory()
    let clock = FixedSessionClock(
        now: Date(timeIntervalSince1970: 1_752_499_800),
        day: try LocalDay("2026-07-14")
    )
    let store = try LocalPokerStore.open(directory: directory.url, clock: clock)
    let human = try SeatID(0)
    _ = try store.sitDown(
        request: CashTableRequest(
            sessionID: try SessionID("public-session"),
            table: try TableID("jade"),
            config: try HandConfig(
                smallBlind: try Chips(50),
                bigBlind: try Chips(100),
                dealer: human
            ),
            humanSeat: human,
            stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
                (try SeatID($0), try Chips(4_000))
            })
        ),
        businessID: try BusinessID("public-buy")
    )
    _ = try store.startHand(id: HandID("public-hand"))

    #expect(store.cashSession?.phase == .handInProgress)
    #expect(store.spectatorObservation?.publicSeats.count == 9)
    let humanObservation = try #require(try store.humanObservation())
    #expect(humanObservation.viewer == human)
    #expect(humanObservation.ownHoleCards.count == 2)
    #expect(store.handRecords().isEmpty)
    #expect(Mirror(reflecting: try #require(store.cashSession)).children.contains {
        ["checkpoint", "deck", "seed", "holeCardsBySeat"].contains($0.label ?? "")
    } == false)
}

@Test func packageAndInternalSessionSymbolsAreUnavailableToOrdinaryImport() throws {
    for probe in PublicBoundaryProbe.allCases {
        try expectPokerSessionTypecheckFailure(probe)
    }
}

private enum PublicBoundaryProbe: String, CaseIterable {
    case cashSession = "let _: CashGameSession.Type = CashGameSession.self"
    case persistedState = "let _: PersistedAppState.Type = PersistedAppState.self"
    case repository = "let _: SessionRepository.Type = SessionRepository.self"
    case fileRepository = "let _: FileSessionRepository.Type = FileSessionRepository.self"
    case checkpoint = "let _: HoldemCheckpoint.Type = HoldemCheckpoint.self"
    case checkpointExport = "_ = game.makeCheckpoint()"
    case checkpointRestore = "_ = HoldemGame.restore"
    case arbitrarySeatObservation = "_ = try store.playerObservation(for: seat1)"
    case explicitSeedStart = "_ = try store.startHand(id: HandID(\"probe-hand\"), seed: 73)"
}

private func expectPokerSessionTypecheckFailure(_ probe: PublicBoundaryProbe) throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let modules = try sessionModulesDirectory(in: packageRoot)
    let source = """
    import PokerCore
    import PokerSession
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 73
    )
    func unavailableStore() -> LocalPokerStore { fatalError() }
    let store = unavailableStore()
    \(probe.rawValue)
    """
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("poker-session-boundary-\(UUID().uuidString).swift")
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
        diagnostics.contains("cannot find")
            || diagnostics.contains("inaccessible")
            || diagnostics.contains("extra argument"),
        Comment(rawValue: diagnostics)
    )
}

private func sessionModulesDirectory(in packageRoot: URL) throws -> URL {
    let build = packageRoot.appendingPathComponent(".build", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: build,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    while let candidate = enumerator?.nextObject() as? URL {
        let modules = candidate.deletingLastPathComponent()
        if candidate.lastPathComponent == "PokerSession.swiftmodule",
           modules.lastPathComponent == "Modules" {
            return modules
        }
    }
    throw PublicBoundaryError.modulesNotFound
}

private final class PublicTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-public-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private enum PublicBoundaryError: Error {
    case modulesNotFound
}
