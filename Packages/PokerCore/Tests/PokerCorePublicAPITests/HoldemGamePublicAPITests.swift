import Foundation
import Testing
import PokerCore

@Test func publicFacadeStartsObservesAndAppliesAnAction() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 42
    )

    let actor = try #require(game.spectatorObservation().currentActor)
    let before = try game.playerObservation(for: actor)
    #expect(before.ownHoleCards.count == 2)
    #expect(before.legalActions != nil)

    let transition = try game.apply(.call, by: actor)

    #expect(game.spectatorObservation().actions.count == 1)
    #expect(transition == game.lastTransition)
    #expect(transition.events == [.actionApplied(seat: actor, action: .call)])
}

@Test func publicFacadeExposesOrderedSeedFreeStartEvents() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 424_242
    )

    #expect(game.lastTransition.events == [
        .handStarted,
        .blindPosted(seat: seat0, amount: try Chips(10)),
        .blindPosted(seat: seat1, amount: try Chips(20)),
        .holeCardsDealt(seat: seat1),
        .holeCardsDealt(seat: seat0),
        .holeCardsDealt(seat: seat1),
        .holeCardsDealt(seat: seat0),
    ])
    let startEvent = try #require(game.lastTransition.events.first)
    #expect(Mirror(reflecting: startEvent).children.contains { $0.label == "seed" } == false)
    let encoded = try JSONEncoder().encode(game.lastTransition)
    let json = try #require(String(data: encoded, encoding: .utf8))
    #expect(json.contains("seed") == false)
    #expect(json.contains("424242") == false)
    let transitionLabels = Mirror(reflecting: game.lastTransition).children.compactMap(\.label)
    #expect(transitionLabels == ["events"])
}

@Test func publicFacadeMirrorDoesNotExposeHiddenState() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 43
    )

    let labels = Mirror(reflecting: game).children.compactMap(\.label)
    #expect(labels.contains("state") == false)
    #expect(labels.contains("deck") == false)
    #expect(labels.contains("seed") == false)
}

@Test func publicFacadeProducesRecordOnlyAfterCompletion() throws {
    let seat0 = try SeatID(0)
    let seat1 = try SeatID(1)
    let game = try HoldemGame.start(
        config: HandConfig(
            smallBlind: try Chips(10),
            bigBlind: try Chips(20),
            dealer: seat0
        ),
        stacks: [seat0: try Chips(1_000), seat1: try Chips(1_000)],
        seed: 44
    )

    #expect(throws: PokerRuleError.illegalAction("hand not complete")) {
        try game.completedRecord()
    }
    let actor = try #require(game.spectatorObservation().currentActor)
    let actionTransition = try game.apply(.fold, by: actor)
    #expect(actionTransition.events == [
        .actionApplied(seat: actor, action: .fold),
        .streetChanged(.showdown),
    ])
    let settlementTransition = try game.advanceIfRoundComplete()
    #expect(settlementTransition == game.lastTransition)
    #expect(settlementTransition.events.last == .handCompleted)
    #expect(settlementTransition.events.contains { event in
        if case .potCreated = event { return true }
        return false
    })
    #expect(settlementTransition.events.contains { event in
        if case .potAwarded = event { return true }
        return false
    })

    let record = try game.completedRecord()
    #expect(record.holeCardsBySeat.count == 2)
    #expect(record.finalStacks.count == 2)
}
