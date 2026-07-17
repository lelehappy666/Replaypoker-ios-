import Testing
@testable import PokerCore

@Test func actorResolverStartsPreflopLeftOfBigBlind() throws {
    let state = try startedFourSeatState(seed: 90)
    let expected = try SeatID(3)

    #expect(BettingActorResolver.expectedActor(in: state) == expected)
}

@Test func actorResolverStartsPostflopLeftOfDealer() throws {
    var state = try startedFourSeatState(seed: 91)
    state.street = .flop
    state.currentBet = try Chips(0)
    state.forcedBringIn = try Chips(0)
    state.actedSinceLastFullRaise = []
    state.lastActedAtBet = [:]
    for index in state.seats.indices {
        state.seats[index].committedThisStreet = try Chips(0)
    }
    let expected = try SeatID(1)

    #expect(BettingActorResolver.expectedActor(in: state) == expected)
}

@Test func actorResolverContinuesAfterLastActionOnCurrentStreet() throws {
    let state = try BettingRules.applying(
        .call,
        by: SeatID(3),
        to: startedFourSeatState(seed: 92)
    )
    let expected = try SeatID(0)

    #expect(BettingActorResolver.expectedActor(in: state) == expected)
}

@Test func actorResolverSkipsFoldedAndAllInSeats() throws {
    var state = try BettingRules.applying(
        .fold,
        by: SeatID(3),
        to: startedFourSeatState(seed: 93)
    )
    state.seats[0].hasFolded = true
    state.seats[1].stack = try Chips(0)
    state.seats[1].isAllIn = true
    let expected = try SeatID(2)

    #expect(BettingActorResolver.expectedActor(in: state) == expected)
}

@Test func 庄家从八号环回零号且跳过弃牌和全下座位仍顺时针() throws {
    var state = try HoldemEngine.start(
        config: Fixtures.standardConfig(dealer: 8),
        stacks: Dictionary(
            uniqueKeysWithValues: (0..<9).map {
                (try! SeatID($0), try! Chips(1_000))
            }
        ),
        seed: 95
    ).state
    state.street = .flop
    state.currentBet = try Chips(0)
    state.forcedBringIn = try Chips(0)
    state.actedSinceLastFullRaise = []
    state.lastActedAtBet = [:]
    for index in state.seats.indices {
        state.seats[index].committedThisStreet = try Chips(0)
    }

    let zero = try SeatID(0)
    #expect(BettingActorResolver.expectedActor(in: state) == zero)

    state.seats[0].hasFolded = true
    state.seats[1].stack = try Chips(0)
    state.seats[1].isAllIn = true
    let two = try SeatID(2)
    #expect(BettingActorResolver.expectedActor(in: state) == two)
}

@Test func actorResolverReturnsNilWhenNoSeatStillNeedsAction() throws {
    var state = try HoldemEngine.start(
        config: Fixtures.standardConfig(dealer: 0),
        stacks: Fixtures.twoStacks(1_000),
        seed: 94
    ).state
    state = try BettingRules.applying(.call, by: SeatID(0), to: state)
    state.currentActor = try SeatID(1)
    state = try BettingRules.applying(.check, by: SeatID(1), to: state)

    #expect(BettingActorResolver.expectedActor(in: state) == nil)
}

private func startedFourSeatState(seed: UInt64) throws -> HoldemState {
    try HoldemEngine.start(
        config: Fixtures.standardConfig(dealer: 0),
        stacks: [
            try SeatID(0): try Chips(1_000),
            try SeatID(1): try Chips(1_000),
            try SeatID(2): try Chips(1_000),
            try SeatID(3): try Chips(1_000),
        ],
        seed: seed
    ).state
}
