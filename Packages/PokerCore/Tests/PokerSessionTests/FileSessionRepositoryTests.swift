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
    let validState = try persistedStateWithRecord()
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

    var testDescription: String { rawValue }

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
        }
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
    var ledger = EntertainmentChipLedger()
    _ = try ledger.buyIn(
        amount: try Chips(5_000),
        table: try TableID("jade"),
        id: try BusinessID("buy-save"),
        at: Date(timeIntervalSince1970: 10)
    )
    return PersistedAppState(
        ledger: ledger,
        activeCashSession: try CashGameSession.make(
            id: try SessionID("session-save"),
            table: try TableID("jade"),
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
    )
}

private func persistedStateWithRecord() throws -> PersistedAppState {
    let id = try HandID("hand-1")
    let stored = StoredHandRecord(
        id: id,
        sessionID: try SessionID("session-history"),
        table: try TableID("jade"),
        startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20),
        localDay: try LocalDay("2026-07-14"),
        handNumber: 1,
        record: try completedRecord()
    )
    return PersistedAppState(
        records: [id: stored],
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
