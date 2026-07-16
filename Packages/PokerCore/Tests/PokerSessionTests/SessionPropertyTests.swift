import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func oneHundredDeterministicFileCommandSequencesPreserveTransactionInvariants() throws {
    var summaries: [PropertySummary] = []
    for seed in 0..<100 {
        let first = try runPropertySequence(seed: UInt64(seed))
        let second = try runPropertySequence(seed: UInt64(seed))
        #expect(first.balance == second.balance, "seed \(seed) 余额不确定")
        #expect(first.records == second.records, "seed \(seed) 记录不确定")
        #expect(first.statistics == second.statistics, "seed \(seed) 统计不确定")
        #expect(first.state == second.state, "seed \(seed) 聚合状态不确定")
        #expect(first.json == second.json, "seed \(seed) JSON 不确定")
        summaries.append(first)
    }

    #expect(summaries.count == 100)
    #expect(Set(summaries.map(\.json)).count > 1)
}

private struct PropertySummary: Equatable {
    let json: Data
    let balance: Chips
    let records: [StoredHandRecord]
    let statistics: PlayerStatisticsView
    let state: PersistedAppState
}

private struct PropertyModel {
    var expectedAccountBalance: Int
    var expectedHumanTable: Int?
    var expectedExternalTable: Int?
    var expectedExternalOffTable = 0
    var expectedTotalAssets: Int

    init(initialAccountBalance: Int) {
        expectedAccountBalance = initialAccountBalance
        expectedTotalAssets = initialAccountBalance
    }

    mutating func receivedGift() {
        expectedAccountBalance += SessionEconomy.dailyGift.rawValue
        expectedTotalAssets += SessionEconomy.dailyGift.rawValue
    }

    mutating func receivedRelief() {
        let delta = SessionEconomy.reliefTarget.rawValue - expectedAccountBalance
        expectedAccountBalance += delta
        expectedTotalAssets += delta
    }

    mutating func boughtIn(human: Int, external: Int) {
        expectedAccountBalance -= human
        expectedHumanTable = human
        expectedExternalTable = external
        expectedTotalAssets += external
    }

    mutating func settled(record: StoredHandRecord, human: SeatID) throws {
        let humanBefore = try #require(expectedHumanTable)
        let externalBefore = try #require(expectedExternalTable)
        let humanDelta = try #require(record.record.chipDeltas[human])
        expectedHumanTable = humanBefore + humanDelta
        expectedExternalTable = externalBefore - humanDelta

        let actualHuman = try #require(record.record.finalStacks[human]).rawValue
        let actualExternal = record.record.finalStacks
            .filter { $0.key != human }
            .values.reduce(0) { $0 + $1.rawValue }
        #expect(actualHuman == expectedHumanTable)
        #expect(actualExternal == expectedExternalTable)
        #expect(record.record.finalStacks.values.reduce(0) { $0 + $1.rawValue } == humanBefore + externalBefore)
    }

    mutating func rebought(amount: Int) {
        expectedAccountBalance -= amount
        expectedHumanTable = (expectedHumanTable ?? 0) + amount
    }

    mutating func left() {
        expectedAccountBalance += expectedHumanTable ?? 0
        expectedExternalOffTable += expectedExternalTable ?? 0
        expectedHumanTable = nil
        expectedExternalTable = nil
    }
}

private struct PropertyLCG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private func runPropertySequence(seed: UInt64) throws -> PropertySummary {
    let directory = try PropertyTemporaryDirectory()
    let clock = FixedSessionClock(
        now: Date(timeIntervalSince1970: 1_752_499_800),
        day: try LocalDay("2026-07-14")
    )
    let lowBalanceScenario = seed.isMultiple(of: 10)
    let initialBalance = lowBalanceScenario ? 1_500 : SessionEconomy.initialBalance.rawValue
    let repository = FileSessionRepository(directory: directory.url)
    if lowBalanceScenario {
        try repository.save(
            PersistedAppState(ledger: EntertainmentChipLedger(balance: try Chips(initialBalance)))
        )
    }

    var store = try LocalPokerStore.open(directory: directory.url, clock: clock)
    let human = try SeatID(1)
    let externalInitial = 8 * 4_000
    var model = PropertyModel(initialAccountBalance: initialBalance)
    var random = PropertyLCG(seed: seed)

    if lowBalanceScenario {
        let reliefID = try BusinessID("relief-\(seed)")
        _ = try store.claimRelief(businessID: reliefID)
        model.receivedRelief()
        _ = try store.claimRelief(businessID: reliefID)
    } else if random.next().isMultiple(of: 2) {
        let giftID = try BusinessID("gift-\(seed)")
        _ = try store.claimDailyGift(businessID: giftID)
        model.receivedGift()
        _ = try store.claimDailyGift(businessID: giftID)
    }
    try auditProperty(store, model: model, human: human)

    let request = try propertyRequest(seed: seed, humanBuyIn: 4_000)
    let buyID = try BusinessID("buy-\(seed)")
    _ = try store.sitDown(request: request, businessID: buyID)
    model.boughtIn(human: 4_000, external: externalInitial)
    _ = try store.sitDown(request: request, businessID: buyID)
    try auditProperty(store, model: model, human: human)

    store = try LocalPokerStore.open(directory: directory.url, clock: clock)
    #expect(store.cashSession?.phase == .readyForHand)
    let handID = try HandID("hand-\(seed)")
    _ = try store.startHand(id: handID, seed: random.next())
    try auditProperty(store, model: model, human: human)

    var didReopenDuringHand = false
    while let actor = store.spectatorObservation?.currentActor {
        let observation = try #require(try store.playerObservation(for: actor))
        let legal = try #require(observation.legalActions)
        let action = choosePropertyAction(
            from: legal,
            actor: actor,
            human: human,
            random: &random
        )
        _ = try store.apply(action, by: actor)
        try auditProperty(store, model: model, human: human)

        if !didReopenDuringHand, store.cashSession?.phase == .handInProgress {
            let before = store.spectatorObservation
            store = try LocalPokerStore.open(directory: directory.url, clock: clock)
            #expect(store.spectatorObservation == before)
            if let reopenedActor = store.spectatorObservation?.currentActor {
                let reopenedObservation = try #require(
                    try store.playerObservation(for: reopenedActor)
                )
                #expect(reopenedObservation.legalActions != nil)
            }
            didReopenDuringHand = true
        }
    }
    if store.cashSession?.phase == .handInProgress {
        _ = try store.advanceIfRoundComplete()
    }
    #expect(store.cashSession?.phase == .settlementPending)
    #expect(!store.handRecords().contains { $0.id == handID })

    let settleID = try BusinessID("settle-\(seed)")
    let archiveMetadata = try makeArchiveMetadata(humanSeat: human)
    let record = try store.commitPendingHand(
        transactionID: settleID,
        archiveMetadata: archiveMetadata
    )
    try model.settled(record: record, human: human)
    #expect(try store.commitPendingHand(
        transactionID: settleID,
        archiveMetadata: archiveMetadata
    ) == record)
    try auditProperty(store, model: model, human: human)

    let humanStack = try #require(model.expectedHumanTable)
    if humanStack < 4_000 {
        let amount = 4_000 - humanStack
        let rebuyID = try BusinessID("rebuy-\(seed)")
        let rebuyAmount = try Chips(amount)
        _ = try store.rebuyHuman(amount: rebuyAmount, businessID: rebuyID)
        model.rebought(amount: amount)
        _ = try store.rebuyHuman(amount: rebuyAmount, businessID: rebuyID)
        try auditProperty(store, model: model, human: human)
    }

    let leaveID = try BusinessID("leave-\(seed)")
    try store.leave(businessID: leaveID)
    model.left()
    try store.leave(businessID: leaveID)
    try auditProperty(store, model: model, human: human)

    let finalState = try repository.load()
    let fileData = try Data(contentsOf: repository.fileURL)
    let summary = PropertySummary(
        json: try canonicalPropertyJSON(fileData),
        balance: store.accountBalance,
        records: store.handRecords(),
        statistics: store.statistics,
        state: finalState
    )
    let reopened = try LocalPokerStore.open(directory: directory.url, clock: clock)
    #expect(reopened.accountBalance == summary.balance)
    #expect(reopened.handRecords() == summary.records)
    #expect(reopened.statistics == summary.statistics)
    return summary
}

private func canonicalPropertyJSON(_ data: Data) throws -> Data {
    let dictionaryArrayKeys: Set<String> = [
        "awards", "chipDeltas", "finalStacks", "handRanksBySeat", "holeCardsBySeat",
        "seatDisplayNames", "settledCommitments", "settledContributions", "stacks",
        "startingStacks", "uncalledReturns",
    ]
    let setArrayKeys: Set<String> = ["eligible", "usedHandIDs", "usedSessionIDs"]

    func stableData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["value": value], options: [.sortedKeys])
    }

    func canonical(_ value: Any, key: String?) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (nestedKey, nested) in dictionary {
                result[nestedKey] = try canonical(nested, key: nestedKey)
            }
            return result
        }
        guard let array = value as? [Any] else { return value }
        let normalized = try array.map { try canonical($0, key: nil) }
        if let key, dictionaryArrayKeys.contains(key), normalized.count.isMultiple(of: 2) {
            let pairs = stride(from: 0, to: normalized.count, by: 2).map {
                [normalized[$0], normalized[$0 + 1]]
            }
            return try pairs.sorted {
                try stableData($0[0]).lexicographicallyPrecedes(stableData($1[0]))
            }.flatMap { $0 }
        }
        if let key, setArrayKeys.contains(key) {
            return try normalized.sorted {
                try stableData($0).lexicographicallyPrecedes(stableData($1))
            }
        }
        return normalized
    }

    let object = try JSONSerialization.jsonObject(with: data)
    return try JSONSerialization.data(
        withJSONObject: canonical(object, key: nil),
        options: [.sortedKeys]
    )
}

private func auditProperty(
    _ store: LocalPokerStore,
    model: PropertyModel,
    human: SeatID
) throws {
    #expect(store.accountBalance.rawValue >= 0)
    #expect(store.accountBalance.rawValue == model.expectedAccountBalance)
    #expect(Set(store.handRecords().map(\.id)).count == store.handRecords().count)
    #expect(store.statistics.completedHands == store.handRecords().count)

    var humanTable = 0
    var externalTable = 0
    if let session = store.cashSession {
        let tableAssets: [SeatID: Int]
        if session.phase == .handInProgress, let observation = store.spectatorObservation {
            tableAssets = Dictionary(uniqueKeysWithValues: observation.publicSeats.map {
                ($0.id, $0.stack.rawValue + $0.committedThisHand.rawValue)
            })
        } else {
            tableAssets = Dictionary(
                uniqueKeysWithValues: session.seats.map { ($0.id, $0.stack.rawValue) }
            )
        }
        humanTable = try #require(tableAssets[human])
        externalTable = tableAssets.filter { $0.key != human }.values.reduce(0, +)
        if session.phase != .settlementPending {
            #expect(humanTable == model.expectedHumanTable)
            #expect(externalTable == model.expectedExternalTable)
        }
    } else {
        #expect(model.expectedHumanTable == nil)
        #expect(model.expectedExternalTable == nil)
    }

    #expect(
        store.accountBalance.rawValue + humanTable + externalTable
            + model.expectedExternalOffTable == model.expectedTotalAssets
    )
}

private func choosePropertyAction(
    from legal: LegalActionSet,
    actor: SeatID,
    human: SeatID,
    random: inout PropertyLCG
) -> PlayerAction {
    if actor == human, legal.canFold { return .fold }
    if legal.canFold, !random.next().isMultiple(of: 4) { return .fold }
    if legal.callAmount != nil { return .call }
    if legal.canCheck { return .check }
    preconditionFailure("合法行动集不应为空")
}

private func propertyRequest(seed: UInt64, humanBuyIn: Int) throws -> CashTableRequest {
    let dealer = try SeatID(0)
    let human = try SeatID(1)
    return CashTableRequest(
        sessionID: try SessionID("property-session-\(seed)"),
        table: try TableID("property-table-\(seed % 5)"),
        config: try HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: dealer
        ),
        humanSeat: human,
        stacks: try Dictionary(uniqueKeysWithValues: (0..<9).map {
            (try SeatID($0), try Chips($0 == human.rawValue ? humanBuyIn : 4_000))
        })
    )
}

private final class PropertyTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("river-club-property-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
