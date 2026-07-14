import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func repositoryReturnsFreshStateOnlyWhenCommittedFileIsMissing() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)

    #expect(try repository.load() == PersistedAppState())

    try Data().write(to: repository.fileURL)
    #expect(throws: PokerSessionError.corruptSnapshot) {
        try repository.load()
    }
}

@Test func saveThenLoadRoundTripsWholeAggregate() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    let state = try persistedStateWithLedgerAndSession()

    try repository.save(state)

    #expect(try repository.load() == state)
    #expect(repository.fileURL.lastPathComponent == "river-club-state-v1.json")
}

@Test func savingAgainAtomicallyReplacesExistingCommittedFile() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    try repository.save(persistedState(balance: 128_500))
    let replacement = try persistedState(balance: 42_000)

    try repository.save(replacement)

    #expect(try repository.load() == replacement)
    #expect(try directory.contents() == [repository.fileURL.lastPathComponent])
}

@Test(arguments: AtomicWriteStage.allCases)
func atomicWriteFailurePreservesCommittedFileAndCleansTemporaryFile(
    stage: AtomicWriteStage
) throws {
    let directory = try TemporaryDirectory()
    let failure = WriteFailureController(stage: stage)
    let writer = AtomicFileWriter { reachedStage in
        try failure.check(reachedStage)
    }
    let repository = FileSessionRepository(directory: directory.url, writer: writer)
    let old = try persistedState(balance: 128_500)
    try repository.save(old)
    failure.isEnabled = true

    #expect(throws: PokerSessionError.persistenceFailed) {
        try repository.save(persistedState(balance: 100))
    }

    #expect(try repository.load() == old)
    #expect(try directory.contents() == [repository.fileURL.lastPathComponent])
}

@Test func unsupportedVersionIsNotMappedToCorruptSnapshot() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    let data = try JSONSerialization.data(
        withJSONObject: [
            "version": 99,
            "ledger": ["balance": 128_500, "entries": []],
            "records": [:],
            "recordOrder": [],
            "statistics": [
                "completedHands": 0,
                "wonHands": 0,
                "totalCommitted": 0,
                "netChange": 0,
                "largestWin": 0,
            ],
        ]
    )
    try data.write(to: repository.fileURL)

    #expect(throws: PokerSessionError.unsupportedVersion(99)) {
        try repository.load()
    }
}

@Test func corruptJSONDoesNotResetAccount() throws {
    let directory = try TemporaryDirectory()
    let repository = FileSessionRepository(directory: directory.url)
    try Data("not-json".utf8).write(to: repository.fileURL)

    #expect(throws: PokerSessionError.corruptSnapshot) {
        try repository.load()
    }
}

@Test func readAndWriteIOFailuresMapToPersistenceFailed() throws {
    let directory = try TemporaryDirectory()
    let missingDirectory = directory.url.appendingPathComponent("missing")
    let writeRepository = FileSessionRepository(directory: missingDirectory)
    #expect(throws: PokerSessionError.persistenceFailed) {
        try writeRepository.save(PersistedAppState())
    }

    let readRepository = FileSessionRepository(directory: directory.url)
    try FileManager.default.createDirectory(at: readRepository.fileURL, withIntermediateDirectories: false)
    #expect(throws: PokerSessionError.persistenceFailed) {
        try readRepository.load()
    }
}

@Test(arguments: AggregateCorruption.allCases)
private func aggregateDecodingRejectsStructuralAndStatisticalCorruption(
    corruption: AggregateCorruption
) throws {
    let validState = try persistedStateWithRecord(
        record: corruption.requiresRaisedAction
            ? completedRecordWithRaise()
            : completedRecord()
    )
    let encoder = JSONEncoder()
    let data = try encoder.encode(validState)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    try corruption.apply(to: &object)
    let corrupted = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PersistedAppState.self, from: corrupted)
    }
}

@Test func aggregateAllowsStatisticsToOutliveDeletedHistory() throws {
    var state = PersistedAppState()
    state.statistics = PlayerStatistics(
        completedHands: 12,
        wonHands: 3,
        totalCommitted: 9_000,
        netChange: -2_000,
        largestWin: 2_500
    )

    let decoded = try JSONDecoder().decode(
        PersistedAppState.self,
        from: JSONEncoder().encode(state)
    )

    #expect(decoded == state)
    #expect(decoded.records.isEmpty)
    #expect(decoded.statistics.completedHands == 12)
}

@Test func aggregateRejectsFewerCompletedHandsThanStoredRecords() throws {
    let state = try persistedStateWithRecord()
    var object = try persistedStateJSONObject(state)
    var statistics = try #require(object["statistics"] as? [String: Any])
    statistics["completedHands"] = 0
    statistics["wonHands"] = 0
    object["statistics"] = statistics

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

@Test func aggregateRejectsDuplicateHandNumberWithinOneSession() throws {
    let state = try persistedStateWithTwoRecords(handNumbers: (1, 3))
    var object = try persistedStateJSONObject(state)
    var records = try #require(object["records"] as? [String: Any])
    var second = try #require(records["hand-2"] as? [String: Any])
    second["handNumber"] = 1
    records["hand-2"] = second
    object["records"] = records

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

@Test func aggregateAllowsHandNumberGapsAndReuseAcrossSessions() throws {
    let withGap = try persistedStateWithTwoRecords(handNumbers: (1, 3))
    #expect(
        try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONEncoder().encode(withGap)
        ) == withGap
    )

    let acrossSessions = try persistedStateWithTwoRecords(
        handNumbers: (1, 1),
        sessionIDs: ("session-history", "another-session")
    )
    #expect(
        try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONEncoder().encode(acrossSessions)
        ) == acrossSessions
    )
}

@Test func aggregateAllowsFullRunoutAndEarlyFoldActionHistories() throws {
    for record in [try completedRecord(), try completedRecordWithFullRunout()] {
        let state = try persistedStateWithRecord(record: record)
        #expect(
            try JSONDecoder().decode(
                PersistedAppState.self,
                from: JSONEncoder().encode(state)
            ) == state
        )
    }
}

private enum AggregateCorruption: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case recordKeyDoesNotMatchID
    case duplicateRecordOrder
    case recordOrderMissingKey
    case nonpositiveHandNumber
    case handEndsBeforeItStarts
    case negativeCompletedHands
    case wonHandsExceedCompletedHands
    case negativeTotalCommitted
    case lossesExceedTotalCommitted
    case negativeLargestWin
    case recordInitialTotalMismatch
    case recordChipDeltaMismatch
    case recordFinalStackKeysMismatch
    case recordContainsDuplicateCard
    case recordActionsAreEmpty
    case recordFoldChangedToCheck
    case recordActionStreetChanged
    case recordRaiseAmountChanged

    var testDescription: String { rawValue }

    var requiresRaisedAction: Bool {
        self == .recordRaiseAmountChanged
    }

    func apply(to object: inout [String: Any]) throws {
        switch self {
        case .recordKeyDoesNotMatchID:
            var records = try #require(object["records"] as? [String: Any])
            let record = records.removeValue(forKey: "hand-1")
            records["another-key"] = record
            object["records"] = records
        case .duplicateRecordOrder:
            object["recordOrder"] = ["hand-1", "hand-1"]
        case .recordOrderMissingKey:
            object["recordOrder"] = []
        case .nonpositiveHandNumber:
            try setRecordValue(0, key: "handNumber", object: &object)
        case .handEndsBeforeItStarts:
            try setRecordValue(-1_000_000_000, key: "endedAt", object: &object)
        case .negativeCompletedHands:
            try setStatistic(-1, key: "completedHands", object: &object)
        case .wonHandsExceedCompletedHands:
            try setStatistic(2, key: "wonHands", object: &object)
        case .negativeTotalCommitted:
            try setStatistic(-1, key: "totalCommitted", object: &object)
        case .lossesExceedTotalCommitted:
            try setStatistic(-101, key: "netChange", object: &object)
        case .negativeLargestWin:
            try setStatistic(-1, key: "largestWin", object: &object)
        case .recordInitialTotalMismatch:
            try mutateCompletedRecord(in: &object) { record in
                record["initialTotalChips"] = 1
            }
        case .recordChipDeltaMismatch:
            try mutateCompletedRecord(in: &object) { record in
                var deltas = try #require(record["chipDeltas"] as? [Any])
                let value = try #require(deltas[1] as? Int)
                deltas[1] = value + 1
                record["chipDeltas"] = deltas
            }
        case .recordFinalStackKeysMismatch:
            try mutateCompletedRecord(in: &object) { record in
                var stacks = try #require(record["finalStacks"] as? [Any])
                stacks.removeLast(2)
                record["finalStacks"] = stacks
            }
        case .recordContainsDuplicateCard:
            try mutateCompletedRecord(in: &object) { record in
                var cardsBySeat = try #require(record["holeCardsBySeat"] as? [Any])
                let firstCards = try #require(cardsBySeat[1] as? [Any])
                var secondCards = try #require(cardsBySeat[3] as? [Any])
                secondCards[0] = firstCards[0]
                cardsBySeat[3] = secondCards
                record["holeCardsBySeat"] = cardsBySeat
            }
        case .recordActionsAreEmpty:
            try mutateCompletedRecord(in: &object) { record in
                record["actions"] = []
            }
        case .recordFoldChangedToCheck:
            try mutateFirstAction(in: &object) { action in
                action["action"] = try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(PlayerAction.check)
                )
            }
        case .recordActionStreetChanged:
            try mutateFirstAction(in: &object) { action in
                action["street"] = Street.flop.rawValue
            }
        case .recordRaiseAmountChanged:
            try mutateFirstAction(in: &object) { action in
                action["action"] = replacingInteger(
                    in: try #require(action["action"]),
                    from: 300,
                    to: 301
                )
            }
        }
    }

    private func mutateFirstAction(
        in object: inout [String: Any],
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        try mutateCompletedRecord(in: &object) { record in
            var actions = try #require(record["actions"] as? [[String: Any]])
            try mutation(&actions[0])
            record["actions"] = actions
        }
    }

    private func replacingInteger(
        in value: Any,
        from oldValue: Int,
        to newValue: Int
    ) -> Any {
        if let integer = value as? Int, integer == oldValue {
            return newValue
        }
        if let array = value as? [Any] {
            return array.map { replacingInteger(in: $0, from: oldValue, to: newValue) }
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues {
                replacingInteger(in: $0, from: oldValue, to: newValue)
            }
        }
        return value
    }

    private func mutateCompletedRecord(
        in object: inout [String: Any],
        mutation: (inout [String: Any]) throws -> Void
    ) throws {
        var records = try #require(object["records"] as? [String: Any])
        var stored = try #require(records["hand-1"] as? [String: Any])
        var record = try #require(stored["record"] as? [String: Any])
        try mutation(&record)
        stored["record"] = record
        records["hand-1"] = stored
        object["records"] = records
    }

    private func setRecordValue(
        _ value: Any,
        key: String,
        object: inout [String: Any]
    ) throws {
        var records = try #require(object["records"] as? [String: Any])
        var record = try #require(records["hand-1"] as? [String: Any])
        record[key] = value
        records["hand-1"] = record
        object["records"] = records
    }

    private func setStatistic(
        _ value: Int,
        key: String,
        object: inout [String: Any]
    ) throws {
        var statistics = try #require(object["statistics"] as? [String: Any])
        statistics[key] = value
        object["statistics"] = statistics
    }
}

private final class WriteFailureController {
    let stage: AtomicWriteStage
    var isEnabled = false

    init(stage: AtomicWriteStage) {
        self.stage = stage
    }

    func check(_ reachedStage: AtomicWriteStage) throws {
        if isEnabled, reachedStage == stage {
            throw InjectedFailure()
        }
    }
}

private struct InjectedFailure: Error {}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}

private func persistedState(balance: Int) throws -> PersistedAppState {
    PersistedAppState(ledger: EntertainmentChipLedger(balance: try Chips(balance)))
}

private func persistedStateWithLedgerAndSession() throws -> PersistedAppState {
    let businessID = try BusinessID("buy-save")
    let table = try TableID("jade")
    var ledger = EntertainmentChipLedger()
    _ = try ledger.buyIn(
        amount: try Chips(5_000),
        table: table,
        id: businessID,
        at: Date(timeIntervalSince1970: 10)
    )
    let session = try CashGameSession.make(
        id: try SessionID("session-save"),
        table: table,
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: try SeatID(0)
        ),
        humanSeat: try SeatID(0),
        stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
            (try SeatID($0), try Chips(5_000))
        })
    )
    let request = CashTableRequest(
        sessionID: session.id,
        table: session.table,
        config: session.config,
        humanSeat: session.humanSeat,
        stacks: session.stacks
    )
    return PersistedAppState(
        ledger: ledger,
        activeCashSession: session,
        commandReceipts: [businessID: .sitDown(request: request, result: session.view)]
    )
}

private func persistedStateWithRecord(
    record: CompletedHandRecord? = nil
) throws -> PersistedAppState {
    let stored = try storedRecord(id: "hand-1", sessionID: "session-history", handNumber: 1)
    let id = stored.id
    let storedRecord = if let record {
        StoredHandRecord(
            id: stored.id,
            sessionID: stored.sessionID,
            table: stored.table,
            startedAt: stored.startedAt,
            endedAt: stored.endedAt,
            localDay: stored.localDay,
            handNumber: stored.handNumber,
            record: record
        )
    } else {
        stored
    }
    return PersistedAppState(
        records: [id: storedRecord],
        recordOrder: [id],
        statistics: PlayerStatistics(
            completedHands: 1,
            wonHands: 1,
            totalCommitted: 100,
            netChange: 100,
            largestWin: 100
        )
    )
}

private func persistedStateWithTwoRecords(
    handNumbers: (Int, Int),
    sessionIDs: (String, String) = ("session-history", "session-history")
) throws -> PersistedAppState {
    let first = try storedRecord(
        id: "hand-1",
        sessionID: sessionIDs.0,
        handNumber: handNumbers.0
    )
    let second = try storedRecord(
        id: "hand-2",
        sessionID: sessionIDs.1,
        handNumber: handNumbers.1
    )
    return PersistedAppState(
        records: [first.id: first, second.id: second],
        recordOrder: [first.id, second.id],
        statistics: PlayerStatistics(
            completedHands: 2,
            wonHands: 1,
            totalCommitted: 200,
            netChange: 0,
            largestWin: 100
        )
    )
}

private func storedRecord(
    id: String,
    sessionID: String,
    handNumber: Int
) throws -> StoredHandRecord {
    StoredHandRecord(
        id: try HandID(id),
        sessionID: try SessionID(sessionID),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20),
        localDay: try LocalDay("2026-07-14"),
        handNumber: handNumber,
        record: try completedRecord()
    )
}

private func persistedStateJSONObject(
    _ state: PersistedAppState
) throws -> [String: Any] {
    try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
    )
}

private func completedRecord() throws -> CompletedHandRecord {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(4_000), seat1: try Chips(4_000)],
        seed: 7
    )
    let actor = try #require(game.spectatorObservation().currentActor)
    try game.apply(.fold, by: actor)
    try game.advanceIfRoundComplete()
    return try game.completedRecord()
}

private func completedRecordWithRaise() throws -> CompletedHandRecord {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(4_000), seat1: try Chips(4_000)],
        seed: 17
    )
    try game.apply(.raiseTo(try Chips(300)), by: seat0)
    try game.apply(.fold, by: seat1)
    try game.advanceIfRoundComplete()
    return try game.completedRecord()
}

private func completedRecordWithFullRunout() throws -> CompletedHandRecord {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(4_000), seat1: try Chips(4_000)],
        seed: 23
    )
    try game.apply(.raiseTo(try Chips(4_000)), by: seat0)
    try game.apply(.call, by: seat1)
    try game.advanceIfRoundComplete()
    return try game.completedRecord()
}
