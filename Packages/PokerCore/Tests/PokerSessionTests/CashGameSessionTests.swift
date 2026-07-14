import Foundation
import PokerCore
import Testing
@testable import PokerSession

@Test func cashSessionRequiresExactlyNinePositiveSeatsIncludingHuman() throws {
    let config = try cashConfig()
    let human = try SeatID(0)
    let lastSeat = try SeatID(8)

    #expect(throws: PokerSessionError.invalidTable) {
        try CashGameSession.make(
            id: try SessionID("s-eight"),
            table: try TableID("jade"),
            config: config,
            humanSeat: human,
            stacks: try cashStacks().filter { $0.key != lastSeat }
        )
    }
    #expect(throws: PokerSessionError.invalidTable) {
        try CashGameSession.make(
            id: try SessionID("s-missing-human"),
            table: try TableID("jade"),
            config: config,
            humanSeat: human,
            stacks: try cashStacks().filter { $0.key != human }
        )
    }

    var zeroStack = try cashStacks()
    zeroStack[try SeatID(8)] = try Chips(0)
    #expect(throws: PokerSessionError.invalidTable) {
        try CashGameSession.make(
            id: try SessionID("s-zero"),
            table: try TableID("jade"),
            config: config,
            humanSeat: human,
            stacks: zeroStack
        )
    }
}

@Test func cashBuyInBoundsAreFortyThroughOneHundredBigBlinds() throws {
    let config = try cashConfig()
    let human = try SeatID(0)

    #expect(throws: PokerSessionError.invalidBuyIn) {
        try CashGameSession.make(
            id: try SessionID("s-low"), table: try TableID("jade"), config: config,
            humanSeat: human, stacks: try cashStacks(human: 3_999)
        )
    }
    _ = try CashGameSession.make(
        id: try SessionID("s-min"), table: try TableID("jade"), config: config,
        humanSeat: human, stacks: try cashStacks(human: 4_000)
    )
    _ = try CashGameSession.make(
        id: try SessionID("s-max"), table: try TableID("jade"), config: config,
        humanSeat: human, stacks: try cashStacks(human: 10_000)
    )
    #expect(throws: PokerSessionError.invalidBuyIn) {
        try CashGameSession.make(
            id: try SessionID("s-high"), table: try TableID("jade"), config: config,
            humanSeat: human, stacks: try cashStacks(human: 10_001)
        )
    }
}

@Test func cashSessionStartsAndExposesOnlySafeObservations() throws {
    var session = try cashSession()
    let transition = try session.startHand(
        id: try HandID("h-safe"), seed: 4, startedAt: .distantPast
    )

    #expect(session.view.phase == .handInProgress)
    #expect(session.view.seats.count == 9)
    #expect(session.view.currentActor != nil)
    #expect(!transition.events.isEmpty)
    let spectator = try #require(session.spectatorObservation())
    #expect(spectator.publicSeats.count == 9)
    let humanObservation = try #require(session.playerObservation(for: try SeatID(0)))
    #expect(humanObservation.ownHoleCards.count == 2)
}

@Test func cashSessionDoesNotReplaceCheckpointAfterIllegalAction() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-atomic"), seed: 4, startedAt: .distantPast)
    let actor = try #require(session.view.currentActor)
    let wrongSeat = try SeatID((actor.rawValue + 1) % 9)
    let before = session.checkpoint

    #expect(throws: PokerRuleError.self) {
        try session.apply(.fold, by: wrongSeat)
    }
    #expect(session.checkpoint == before)
    #expect(session.view.currentActor == actor)
}

@Test func completedCashHandBlocksCommandsUntilCommitted() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h1"), seed: 4, startedAt: .distantPast)
    try finishCashHandByFolding(session: &session)

    #expect(session.view.phase == .settlementPending)
    let expectedHandID = try HandID("h1")
    #expect(session.pendingHand?.id == expectedHandID)
    #expect(throws: PokerSessionError.settlementPending) {
        try session.startHand(id: try HandID("h2"), seed: 5, startedAt: .distantFuture)
    }
    #expect(throws: PokerSessionError.settlementPending) {
        try session.addChips(try Chips(100), to: try SeatID(0))
    }
    #expect(throws: PokerSessionError.settlementPending) {
        try session.leave()
    }
}

@Test func committingCashHandAdvancesDealerAndPreservesFinalStacks() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h1"), seed: 4, startedAt: .distantPast)
    try finishCashHandByFolding(session: &session)
    let pending = try #require(session.pendingHand)

    try session.markHandCommitted(pending.id)

    let expectedDealer = try SeatID(1)
    #expect(session.view.completedHands == 1)
    #expect(session.view.dealer == expectedDealer)
    #expect(session.view.phase == .readyForNextHand)
    #expect(Dictionary(uniqueKeysWithValues: session.view.seats.map { ($0.id, $0.stack) }) == pending.record.finalStacks)
    #expect(session.pendingHand == nil)
    #expect(session.checkpoint == nil)
}

@Test func cashSessionRejectsWrongSettlementIDWithoutMutation() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h1"), seed: 4, startedAt: .distantPast)
    try finishCashHandByFolding(session: &session)
    let before = session

    #expect(throws: PokerSessionError.handNotComplete) {
        try session.markHandCommitted(try HandID("other"))
    }
    #expect(session == before)
}

@Test func cashSessionRestoresTheSameSafeObservation() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-restore"), seed: 41, startedAt: .distantPast)
    let actor = try #require(session.view.currentActor)
    try session.apply(.fold, by: actor)
    let expectedSpectator = session.spectatorObservation()
    let expectedHuman = try session.playerObservation(for: try SeatID(0))

    let data = try JSONEncoder().encode(session)
    let restored = try JSONDecoder().decode(CashGameSession.self, from: data)

    #expect(restored.view == session.view)
    #expect(restored.spectatorObservation() == expectedSpectator)
    #expect(try restored.playerObservation(for: try SeatID(0)) == expectedHuman)
}

@Test func cashSessionRejectsCheckpointWithContradictoryRestoredPhase() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-corrupt"), seed: 41, startedAt: .distantPast)
    let encoded = try JSONEncoder().encode(session)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["phase"] = CashSessionPhase.readyForHand.rawValue
    let corrupted = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CashGameSession.self, from: corrupted)
    }
}

@Test func cashSessionRejectsActiveCheckpointFromAnotherSession() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-victim"), seed: 41, startedAt: .distantPast)

    var donor = try CashGameSession.make(
        id: try SessionID("session-donor"),
        table: try TableID("ruby"),
        config: try cashConfig(dealer: 1),
        humanSeat: try SeatID(0),
        stacks: try cashStacks(human: 5_000)
    )
    try donor.startHand(id: try HandID("h-donor"), seed: 99, startedAt: .distantFuture)

    var victimJSON = try cashSessionJSONObject(session)
    let donorJSON = try cashSessionJSONObject(donor)
    victimJSON["checkpoint"] = donorJSON["checkpoint"]
    let corrupted = try JSONSerialization.data(withJSONObject: victimJSON)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CashGameSession.self, from: corrupted)
    }
}

@Test func cashSessionRejectsRealTwoSeatCheckpointInsideNineSeatSession() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-nine"), seed: 41, startedAt: .distantPast)

    let twoSeatGame = try makeTwoSeatGame()
    let checkpointData = try JSONEncoder().encode(twoSeatGame.makeCheckpoint())
    let twoSeatCheckpoint = try JSONSerialization.jsonObject(with: checkpointData)
    var victimJSON = try cashSessionJSONObject(session)
    victimJSON["checkpoint"] = twoSeatCheckpoint
    let corrupted = try JSONSerialization.data(withJSONObject: victimJSON)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CashGameSession.self, from: corrupted)
    }
}

@Test func cashSessionRejectsPendingSettlementFromAnotherSession() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-victim"), seed: 41, startedAt: .distantPast)
    try finishCashHandByFolding(session: &session)

    var donor = try CashGameSession.make(
        id: try SessionID("session-donor"),
        table: try TableID("ruby"),
        config: try cashConfig(dealer: 1),
        humanSeat: try SeatID(0),
        stacks: try cashStacks(human: 5_000)
    )
    try donor.startHand(id: try HandID("h-donor"), seed: 99, startedAt: .distantFuture)
    try finishCashHandByFolding(session: &donor)

    var victimJSON = try cashSessionJSONObject(session)
    let donorJSON = try cashSessionJSONObject(donor)
    victimJSON["checkpoint"] = donorJSON["checkpoint"]
    victimJSON["pendingHand"] = donorJSON["pendingHand"]
    victimJSON["activeHandID"] = donorJSON["activeHandID"]
    victimJSON["activeHandStartedAt"] = donorJSON["activeHandStartedAt"]
    let corrupted = try JSONSerialization.data(withJSONObject: victimJSON)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CashGameSession.self, from: corrupted)
    }
}

@Test func committingCashHandRejectsTamperedTwoSeatRecordWithoutMutation() throws {
    var session = try cashSession()
    try session.startHand(id: try HandID("h-nine"), seed: 41, startedAt: .distantPast)
    try finishCashHandByFolding(session: &session)
    let pending = try #require(session.pendingHand)

    session.pendingHand = PendingCashHand(
        id: pending.id,
        startedAt: pending.startedAt,
        record: try makeCompletedTwoSeatRecord()
    )
    let beforeCommit = session

    #expect(throws: PokerSessionError.corruptSnapshot) {
        try session.markHandCommitted(pending.id)
    }
    #expect(session == beforeCommit)
}

@Test func cashSessionAddChipsIsCheckedAndOnlyAllowedWhileReady() throws {
    var session = try cashSession(human: 4_000)
    let human = try SeatID(0)
    let expectedStack = try Chips(5_000)
    try session.addChips(try Chips(1_000), to: human)
    #expect(session.view.seats.first { $0.id == human }?.stack == expectedStack)

    #expect(throws: PokerSessionError.invalidBuyIn) {
        try session.addChips(try Chips(0), to: human)
    }
    #expect(throws: PokerSessionError.invalidBuyIn) {
        try session.addChips(try Chips(6_000), to: try SeatID(0))
    }

    try session.startHand(id: try HandID("h-add"), seed: 8, startedAt: .distantPast)
    #expect(throws: PokerSessionError.invalidLifecycle) {
        try session.addChips(try Chips(100), to: try SeatID(0))
    }
    #expect(throws: PokerSessionError.invalidLifecycle) {
        try session.leave()
    }
}

@Test func cashSessionDoesNotInventChipsForBustedSeats() throws {
    var session = try cashSession()
    session.stacks[try SeatID(8)] = try Chips(0)
    let before = session

    #expect(throws: PokerSessionError.invalidTable) {
        try session.startHand(id: try HandID("h-zero"), seed: 9, startedAt: .distantPast)
    }
    #expect(session == before)
}

private func cashConfig(dealer: Int = 0) throws -> HandConfig {
    try HandConfig(
        smallBlind: try Chips(50),
        bigBlind: try Chips(100),
        dealer: try SeatID(dealer)
    )
}

private func cashStacks(human: Int = 4_000) throws -> [SeatID: Chips] {
    try Dictionary(uniqueKeysWithValues: (0..<9).map { rawSeat in
        (try SeatID(rawSeat), try Chips(rawSeat == 0 ? human : 4_000))
    })
}

private func cashSession(human: Int = 4_000) throws -> CashGameSession {
    try CashGameSession.make(
        id: try SessionID("session-jade"),
        table: try TableID("jade"),
        config: try cashConfig(),
        humanSeat: try SeatID(0),
        stacks: try cashStacks(human: human)
    )
}

private func finishCashHandByFolding(session: inout CashGameSession) throws {
    while let actor = session.view.currentActor {
        try session.apply(.fold, by: actor)
    }
    if session.view.phase == .handInProgress {
        try session.advanceIfRoundComplete()
    }
}

private func cashSessionJSONObject(
    _ session: CashGameSession
) throws -> [String: Any] {
    let data = try JSONEncoder().encode(session)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func makeTwoSeatGame() throws -> HoldemGame {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    return try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(50),
            bigBlind: try Chips(100),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(4_000), seat1: try Chips(4_000)],
        seed: 73
    )
}

private func makeCompletedTwoSeatRecord() throws -> CompletedHandRecord {
    let game = try makeTwoSeatGame()
    let actor = try #require(game.spectatorObservation().currentActor)
    try game.apply(.fold, by: actor)
    try game.advanceIfRoundComplete()
    return try game.completedRecord()
}
