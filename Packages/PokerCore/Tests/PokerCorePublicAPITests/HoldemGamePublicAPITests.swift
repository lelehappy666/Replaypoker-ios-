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

    try game.apply(.call, by: actor)

    #expect(game.spectatorObservation().actions.count == 1)
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
    try game.apply(.fold, by: actor)
    try game.advanceIfRoundComplete()

    let record = try game.completedRecord()
    #expect(record.holeCardsBySeat.count == 2)
    #expect(record.finalStacks.count == 2)
}
