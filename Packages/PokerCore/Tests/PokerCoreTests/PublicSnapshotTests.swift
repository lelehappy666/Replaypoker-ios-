import Foundation
import Testing
@testable import PokerCore

@Test func playerObservationContainsOnlyOwnHoleCards() throws {
    let state = try startedThreeSeatState()
    let viewer = try SeatID(0)

    let observation = try PlayerObservation(state: state, viewer: viewer)

    #expect(observation.viewer == viewer)
    #expect(observation.ownHoleCards == state.seats.first { $0.id == viewer }?.holeCards)
    #expect(observation.publicSeats.count == 3)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "deck" } == false)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "seed" } == false)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "opponentHoleCards" } == false)
    #expect(observation.publicSeats.allSatisfy {
        Mirror(reflecting: $0).children.contains { $0.label == "holeCards" } == false
    })
}

@Test func spectatorObservationContainsNoHoleCards() throws {
    let observation = SpectatorObservation(state: try startedThreeSeatState())

    #expect(Mirror(reflecting: observation).children.contains { $0.label == "holeCards" } == false)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "deck" } == false)
    #expect(Mirror(reflecting: observation).children.contains { $0.label == "seed" } == false)
    #expect(observation.publicSeats.allSatisfy {
        Mirror(reflecting: $0).children.contains { $0.label == "holeCards" } == false
    })
}

@Test func playerObservationRejectsValidButUnseatedViewer() throws {
    let state = try startedThreeSeatState()

    #expect(throws: PokerRuleError.invalidSeat) {
        try PlayerObservation(state: state, viewer: SeatID(8))
    }
}

@Test func playerObservationOnlyOffersActionsToCurrentActor() throws {
    let state = try startedThreeSeatState()
    let actor = try #require(state.currentActor)
    let observer = try #require(state.seats.map(\.id).first { $0 != actor })

    #expect(try PlayerObservation(state: state, viewer: actor).legalActions != nil)
    #expect(try PlayerObservation(state: state, viewer: observer).legalActions == nil)
}

@Test func observationsPreserveActionStreetWithoutRebuildingEvents() throws {
    let started = try startedThreeSeatState()
    let actor = try #require(started.currentActor)
    let acted = try HoldemEngine.applying(.call, by: actor, to: started).state

    let player = try PlayerObservation(state: acted, viewer: actor)
    let spectator = SpectatorObservation(state: acted)

    #expect(player.actions == acted.actionHistory)
    #expect(spectator.actions == acted.actionHistory)
    #expect(player.actions.last?.street == .preflop)
}

@Test func incompleteHandCannotCreateHistoryRecord() throws {
    let state = try startedThreeSeatState()

    #expect(throws: PokerRuleError.illegalAction("hand not complete")) {
        try CompletedHandRecord(state: state)
    }
}

@Test func completedRecordContainsFoldedPlayersCards() throws {
    let state = try completedHandWithFoldedPlayers()
    let record = try CompletedHandRecord(state: state)

    #expect(record.holeCardsBySeat.count == state.dealtInSeats.count)
    for seat in state.dealtInSeats {
        #expect(record.holeCardsBySeat[seat.id] == seat.holeCards)
    }
    #expect(state.foldedSeats.count == 2)
    #expect(state.foldedSeats.allSatisfy { record.holeCardsBySeat[$0]?.count == 2 })
}

@Test func completedRecordPreservesAuditableSettlementSources() throws {
    let state = try Fixtures.resolveThreeWayAllInWithTwoSidePots().state
    let record = try CompletedHandRecord(state: state)

    #expect(record.config == state.config)
    #expect(record.communityCards == state.communityCards)
    #expect(record.actions == state.actionHistory)
    #expect(record.pots == state.settledPots)
    #expect(record.awards == state.awards)
    #expect(record.uncalledReturns == state.uncalledReturns)
    #expect(record.startingStacks == state.startingStacks)
    #expect(record.settledCommitments == state.settledCommitments)
    #expect(record.settledContributions == state.settledContributions)
    #expect(record.initialTotalChips == state.initialTotalChips)
    #expect(record.finalStacks == Dictionary(uniqueKeysWithValues: state.seats.map { ($0.id, $0.stack) }))
    #expect(Set(record.chipDeltas.keys) == Set(state.startingStacks.keys))
    #expect(Set(record.handRanksBySeat.keys) == Set(state.dealtInSeats.map(\.id)))
}

@Test func completedRecordRejectsForgedCompleteState() throws {
    var state = try Fixtures.resolveThreeWayAllInWithTwoSidePots().state
    let winner = try #require(state.awards.keys.first)
    state.awards[winner] = try Chips(state.awards[winner]!.rawValue + 1)

    #expect(throws: PokerRuleError.self) {
        try CompletedHandRecord(state: state)
    }
}

@Test func completedRecordFreezesRanksStacksAndSignedDeltas() throws {
    let state = try Fixtures.resolveThreeWayAllInWithTwoSidePots().state
    let record = try CompletedHandRecord(state: state)

    for seat in state.dealtInSeats {
        let expectedRank = try HandEvaluator.best(of: seat.holeCards + state.communityCards)
        #expect(record.handRanksBySeat[seat.id] == expectedRank)
        #expect(record.finalStacks[seat.id] == seat.stack)
        #expect(record.chipDeltas[seat.id] == seat.stack.rawValue - state.startingStacks[seat.id]!.rawValue)
    }
}

@Test func foldCompletionWithoutFullBoardHasNoSyntheticHandRanks() throws {
    let state = try completedHandWithFoldedPlayers()

    #expect(try CompletedHandRecord(state: state).handRanksBySeat.isEmpty)
}

@Test func publicSnapshotsAndCompletedRecordRoundTripThroughCodable() throws {
    let player = try PlayerObservation(state: startedThreeSeatState(), viewer: SeatID(0))
    let spectator = SpectatorObservation(state: try startedThreeSeatState())
    let record = try CompletedHandRecord(state: Fixtures.resolveThreeWayAllInWithTwoSidePots().state)

    try expectRoundTrip(player)
    try expectRoundTrip(spectator)
    try expectRoundTrip(record)
}

private func startedThreeSeatState() throws -> HoldemState {
    try HoldemEngine.start(
        config: Fixtures.standardConfig(dealer: 0),
        stacks: [
            try SeatID(0): try Chips(1_000),
            try SeatID(1): try Chips(1_000),
            try SeatID(2): try Chips(1_000),
        ],
        seed: 900
    ).state
}

private func completedHandWithFoldedPlayers() throws -> HoldemState {
    let started = try startedThreeSeatState()
    let firstActor = try #require(started.currentActor)
    let firstFold = try HoldemEngine.applying(.fold, by: firstActor, to: started).state
    let secondActor = try #require(firstFold.currentActor)
    let showdown = try HoldemEngine.applying(.fold, by: secondActor, to: firstFold).state
    return try HoldemEngine.advanceIfRoundComplete(showdown).state
}

private func expectRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(Value.self, from: data) == value)
}
