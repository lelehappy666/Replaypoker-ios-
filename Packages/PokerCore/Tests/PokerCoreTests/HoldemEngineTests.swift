import Testing
@testable import PokerCore

@Test func nineSeatHandPostsBlindsDealsTwoCardsAndActsLeftOfBigBlind() throws {
    let config = try standardConfig()

    let result = try HoldemEngine.start(
        config: config,
        stacks: Fixtures.nineStacks(10_000),
        seed: 1
    )

    #expect(result.state.seats.allSatisfy { $0.holeCards.count == 2 })
    #expect(result.state.smallBlindSeat == SeatID(rawValue: 1)!)
    #expect(result.state.bigBlindSeat == SeatID(rawValue: 2)!)
    #expect(result.state.currentActor == SeatID(rawValue: 3)!)
    #expect(result.events.contains(.blindPosted(
        seat: SeatID(rawValue: 1)!,
        amount: Chips(rawValue: 50)!
    )))
    #expect(result.events.contains(.blindPosted(
        seat: SeatID(rawValue: 2)!,
        amount: Chips(rawValue: 100)!
    )))
}

@Test func headsUpDealerPostsSmallBlindAndActsFirstPreflop() throws {
    let result = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(10_000),
        seed: 1
    )

    #expect(result.state.dealer == result.state.smallBlindSeat)
    #expect(result.state.bigBlindSeat == SeatID(rawValue: 1)!)
    #expect(result.state.currentActor == result.state.dealer)
}

@Test func holeCardsAreDealtOneAtATimeStartingLeftOfDealer() throws {
    let result = try HoldemEngine.start(
        config: standardConfig(),
        stacks: stacks([0, 2, 5], amount: 1_000),
        seed: 77
    )
    var expectedDeck = Deck.shuffled(seed: 77)
    var expected: [SeatID: [Card]] = [:]
    let order = [SeatID(rawValue: 2)!, SeatID(rawValue: 5)!, SeatID(rawValue: 0)!]
    for _ in 0..<2 {
        for seat in order {
            expected[seat, default: []].append(try expectedDeck.draw())
        }
    }

    for seat in result.state.seats {
        #expect(seat.holeCards == expected[seat.id])
    }
    #expect(result.events.compactMap { event -> SeatID? in
        guard case let .holeCardsDealt(seat) = event else { return nil }
        return seat
    } == order + order)
}

@Test func aRoundNeedsEveryActionableSeatToActAtTheCurrentBet() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(10_000),
        seed: 1
    )

    let called = try HoldemEngine.applying(.call, by: SeatID(0), to: started.state)
    #expect(called.state.street == .preflop)
    #expect(called.state.currentActor == SeatID(rawValue: 1)!)

    let checked = try HoldemEngine.applying(.check, by: SeatID(1), to: called.state)
    #expect(checked.state.street == .flop)
    #expect(checked.state.communityCards.count == 3)
}

@Test func streetsDealThreeThenOneThenOneAndActLeftOfDealer() throws {
    var state = try Fixtures.completePreflopState()
    #expect(state.street == .flop)
    #expect(state.communityCards.count == 3)
    #expect(state.currentActor == SeatID(rawValue: 1)!)
    #expect(state.actedSinceLastFullRaise.isEmpty)
    #expect(state.lastActedAtBet.isEmpty)

    state = try completeHeadsUpCheckRound(state)
    #expect(state.street == .turn)
    #expect(state.communityCards.count == 4)
    #expect(state.currentActor == SeatID(rawValue: 1)!)

    state = try completeHeadsUpCheckRound(state)
    #expect(state.street == .river)
    #expect(state.communityCards.count == 5)

    state = try completeHeadsUpCheckRound(state)
    #expect(state.street == .showdown)
    #expect(state.communityCards.count == 5)
    #expect(state.currentActor == nil)
}

@Test func nextActorSkipsFoldedAllInAndSittingOutSeats() throws {
    var started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 0)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 3)!: Chips(rawValue: 1_000)!,
        ],
        seed: 9
    ).state
    started.seats[2].isSittingOut = true

    let folded = try HoldemEngine.applying(.fold, by: SeatID(3), to: started)

    #expect(folded.state.seats.first { $0.id == SeatID(rawValue: 0)! }?.isAllIn == true)
    #expect(folded.state.currentActor == SeatID(rawValue: 1)!)
}

@Test func allRemainingPlayersAllInAutomaticallyRunOutTheBoard() throws {
    let result = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 50)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 100)!,
        ],
        seed: 12
    )

    #expect(result.state.street == .showdown)
    #expect(result.state.communityCards.count == 5)
    #expect(result.state.currentActor == nil)
    #expect(result.events.compactMap { event -> Street? in
        guard case let .streetChanged(street) = event else { return nil }
        return street
    } == [.flop, .turn, .river, .showdown])
}

@Test func startRejectsFewerThanTwoPlayers() throws {
    #expect(throws: PokerRuleError.insufficientPlayers) {
        try HoldemEngine.start(
            config: standardConfig(),
            stacks: [SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!],
            seed: 1
        )
    }
}

@Test func identicalSeedReproducesCardsAndEvents() throws {
    let first = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.nineStacks(1_000),
        seed: 42
    )
    let second = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.nineStacks(1_000),
        seed: 42
    )

    #expect(first == second)
}

@Test func eventsFollowMutationOrderForStartAndRoundAdvance() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(1_000),
        seed: 5
    )
    #expect(started.events == [
        .handStarted(seed: 5),
        .blindPosted(seat: SeatID(rawValue: 0)!, amount: Chips(rawValue: 50)!),
        .blindPosted(seat: SeatID(rawValue: 1)!, amount: Chips(rawValue: 100)!),
        .holeCardsDealt(seat: SeatID(rawValue: 1)!),
        .holeCardsDealt(seat: SeatID(rawValue: 0)!),
        .holeCardsDealt(seat: SeatID(rawValue: 1)!),
        .holeCardsDealt(seat: SeatID(rawValue: 0)!),
    ])

    let called = try HoldemEngine.applying(.call, by: SeatID(0), to: started.state)
    #expect(called.events == [.actionApplied(seat: SeatID(rawValue: 0)!, action: .call)])
    let checked = try HoldemEngine.applying(.check, by: SeatID(1), to: called.state)
    #expect(checked.events.first == .actionApplied(seat: SeatID(rawValue: 1)!, action: .check))
    #expect(checked.events.dropFirst().first == .streetChanged(.flop))
    #expect(checked.events.last == .communityCardsDealt(checked.state.communityCards))
}

private func standardConfig() throws -> HandConfig {
    try HandConfig(
        smallBlind: Chips(50),
        bigBlind: Chips(100),
        dealer: SeatID(0)
    )
}

private func stacks(_ seats: [Int], amount: Int) -> [SeatID: Chips] {
    Dictionary(uniqueKeysWithValues: seats.map {
        (SeatID(rawValue: $0)!, Chips(rawValue: amount)!)
    })
}

private func completeHeadsUpCheckRound(_ state: HoldemState) throws -> HoldemState {
    let first = try #require(state.currentActor)
    let afterFirst = try HoldemEngine.applying(.check, by: first, to: state)
    let second = try #require(afterFirst.state.currentActor)
    return try HoldemEngine.applying(.check, by: second, to: afterFirst.state).state
}
