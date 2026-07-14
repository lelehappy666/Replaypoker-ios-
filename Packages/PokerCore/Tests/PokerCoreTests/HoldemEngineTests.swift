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

@Test func shortBigBlindStillCreatesTheNominalPreflopBringIn() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 30)!,
        ],
        seed: 2
    )

    let smallBlind = try #require(started.state.seats.first { $0.id == SeatID(rawValue: 1)! })
    let bigBlind = try #require(started.state.seats.first { $0.id == SeatID(rawValue: 2)! })
    #expect(smallBlind.committedThisStreet == Chips(rawValue: 50)!)
    #expect(bigBlind.committedThisStreet == Chips(rawValue: 30)!)
    #expect(bigBlind.isAllIn)
    #expect(started.state.currentBet == Chips(rawValue: 100)!)
    #expect(started.state.forcedBringIn == Chips(rawValue: 100)!)
    #expect(
        try BettingRules.legalActions(for: SeatID(0), in: started.state).callAmount
            == Chips(rawValue: 100)!
    )
    let called = try HoldemEngine.applying(.call, by: SeatID(0), to: started.state)
    #expect(called.state.currentActor == SeatID(rawValue: 1)!)
    #expect(
        try BettingRules.legalActions(for: SeatID(1), in: called.state).callAmount
            == Chips(rawValue: 50)!
    )
}

@Test func soleActionablePlayerRunsOutAfterMatchingAnAllInOpponent() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 100)!,
        ],
        seed: 3
    )

    #expect(started.state.street == .preflop)
    #expect(started.state.currentActor == SeatID(rawValue: 0)!)
    #expect(
        try BettingRules.legalActions(for: SeatID(0), in: started.state).callAmount
            == Chips(rawValue: 50)!
    )
    let called = try HoldemEngine.applying(.call, by: SeatID(0), to: started.state)

    #expect(called.state.street == .showdown)
    #expect(called.state.communityCards.count == 5)
    #expect(called.state.currentActor == nil)
    let cards = try #require(
        called.state.communityCards.count == 5 ? called.state.communityCards : nil
    )
    #expect(called.events == [
        .actionApplied(seat: SeatID(rawValue: 0)!, action: .call),
        .streetChanged(.flop),
        .communityCardsDealt(Array(cards[0..<3])),
        .streetChanged(.turn),
        .communityCardsDealt([cards[3]]),
        .streetChanged(.river),
        .communityCardsDealt([cards[4]]),
        .streetChanged(.showdown),
    ])
}

@Test func foldingLeavesMatchedBigBlindToRunOutWithoutChecking() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 100)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 1_000)!,
        ],
        seed: 14
    )
    let utgAllIn = try HoldemEngine.applying(.allIn, by: SeatID(0), to: started.state)

    let smallBlindFolded = try HoldemEngine.applying(
        .fold,
        by: SeatID(1),
        to: utgAllIn.state
    )

    #expect(smallBlindFolded.state.street == .showdown)
    #expect(smallBlindFolded.state.communityCards.count == 5)
    #expect(smallBlindFolded.state.currentActor == nil)
    #expect(smallBlindFolded.events.first == .actionApplied(
        seat: SeatID(rawValue: 1)!,
        action: .fold
    ))
    #expect(smallBlindFolded.events.dropFirst().compactMap { event -> Street? in
        guard case let .streetChanged(street) = event else { return nil }
        return street
    } == [.flop, .turn, .river, .showdown])
}

@Test func foldingLeavesUnmatchedBigBlindToCallOrFold() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 150)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 1_000)!,
        ],
        seed: 15
    )
    let utgAllIn = try HoldemEngine.applying(.allIn, by: SeatID(0), to: started.state)

    let smallBlindFolded = try HoldemEngine.applying(
        .fold,
        by: SeatID(1),
        to: utgAllIn.state
    )

    #expect(smallBlindFolded.state.street == .preflop)
    #expect(smallBlindFolded.state.currentActor == SeatID(rawValue: 2)!)
    let legal = try BettingRules.legalActions(for: SeatID(2), in: smallBlindFolded.state)
    #expect(legal.callAmount == Chips(rawValue: 50)!)
    #expect(legal.canFold)
}

@Test func showdownSettlesAndCompletedStateIsNoOpForPublicAdvance() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(1_000),
        seed: 16
    )
    let showdown = try HoldemEngine.applying(.fold, by: SeatID(0), to: started.state).state

    let showdownResult = try HoldemEngine.advanceIfRoundComplete(showdown)
    #expect(showdownResult.state.street == .complete)
    #expect(showdownResult.events.last == .handCompleted)

    let completeResult = try HoldemEngine.advanceIfRoundComplete(showdownResult.state)
    #expect(completeResult == EngineResult(state: showdownResult.state, events: []))
}

@Test func foldingSmallBlindNormalizesShortBigBlindShowdown() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 30)!,
        ],
        seed: 20
    )

    let folded = try HoldemEngine.applying(.fold, by: SeatID(0), to: started.state)

    #expect(folded.state.street == .showdown)
    #expect(folded.state.forcedBringIn == Chips(rawValue: 0)!)
    #expect(folded.state.currentBet == Chips(rawValue: 50)!)
    try BettingRules.validateStructuralState(folded.state)
    let settled = try HoldemEngine.advanceIfRoundComplete(folded.state)
    let seatZero = SeatID(rawValue: 0)!
    let seatOne = SeatID(rawValue: 1)!
    #expect(settled.state.street == .complete)
    #expect(settled.state.seats.first { $0.id == seatZero }?.stack == Chips(rawValue: 970)!)
    #expect(settled.state.seats.first { $0.id == seatOne }?.stack == Chips(rawValue: 60)!)
    #expect(settled.state.settledPots == [
        Pot(amount: Chips(rawValue: 60)!, eligible: [seatOne]),
    ])
    #expect(settled.state.awards == [seatOne: Chips(rawValue: 60)!])
    #expect(settled.state.uncalledReturns == [seatZero: Chips(rawValue: 20)!])
    #expect(settled.events == [
        .uncalledBetReturned(seat: seatZero, amount: Chips(rawValue: 20)!),
        .potCreated(Pot(amount: Chips(rawValue: 60)!, eligible: [seatOne])),
        .potAwarded(
            potIndex: 0,
            winners: [seatOne],
            amounts: [seatOne: Chips(rawValue: 60)!]
        ),
        .handCompleted,
    ])
    #expect(settled.state.uncalledReturns.values.reduce(0) { $0 + $1.rawValue }
        + settled.state.settledPots.reduce(0) { $0 + $1.amount.rawValue } == 80)
    #expect(settled.state.totalSeatChips == settled.state.initialTotalChips)
}

@Test func publicAdvanceNormalizesShortBigBlindTerminalTransition() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 30)!,
        ],
        seed: 21
    )
    var folded = try BettingRules.applying(.fold, by: SeatID(0), to: started.state)
    folded.currentActor = nil
    try BettingRules.validateStructuralState(folded)

    let result = try HoldemEngine.advanceIfRoundComplete(folded)

    #expect(result.state.street == .showdown)
    #expect(result.state.forcedBringIn == Chips(rawValue: 0)!)
    #expect(result.state.currentBet == Chips(rawValue: 50)!)
    try BettingRules.validateStructuralState(result.state)
    let settled = try HoldemEngine.advanceIfRoundComplete(result.state)
    #expect(settled.state.street == .complete)
    #expect(settled.state.awards == [SeatID(rawValue: 1)!: Chips(rawValue: 60)!])
    #expect(settled.state.totalSeatChips == settled.state.initialTotalChips)
}

@Test func allInBettingStateWithoutActorCanAdvance() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(100),
        seed: 17
    )
    var allIn = try BettingRules.applying(.call, by: SeatID(0), to: started.state)
    allIn.currentActor = nil

    let result = try HoldemEngine.advanceIfRoundComplete(allIn)

    #expect(result.state.street == .showdown)
    #expect(result.state.communityCards.count == 5)
    #expect(result.state.currentActor == nil)
}

@Test func bettingStateWithActionablePlayerRequiresActorBeforeAdvance() throws {
    var state = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(1_000),
        seed: 18
    ).state
    state.currentActor = nil
    let snapshot = state

    #expect(throws: PokerRuleError.invalidState("invalid actor")) {
        try HoldemEngine.advanceIfRoundComplete(state)
    }
    #expect(state == snapshot)
}

@Test func terminalNoOpStillRejectsCorruptedAccounting() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(1_000),
        seed: 19
    )
    var showdown = try HoldemEngine.applying(.fold, by: SeatID(0), to: started.state).state
    showdown.unallocatedPot = Chips(rawValue: showdown.unallocatedPot.rawValue + 1)!

    #expect(throws: PokerRuleError.invalidState("unallocated pot mismatch")) {
        try HoldemEngine.advanceIfRoundComplete(showdown)
    }
}

@Test func publicAdvanceRejectsCorruptedAccountingAndActorState() throws {
    let valid = try Fixtures.completePreflopState()

    var wrongPot = valid
    wrongPot.unallocatedPot = Chips(rawValue: wrongPot.unallocatedPot.rawValue + 1)!
    let wrongPotSnapshot = wrongPot
    #expect(throws: PokerRuleError.invalidState("unallocated pot mismatch")) {
        try HoldemEngine.advanceIfRoundComplete(wrongPot)
    }
    #expect(wrongPot == wrongPotSnapshot)

    var wrongCommitment = valid
    wrongCommitment.seats[0].committedThisHand = Chips(
        rawValue: wrongCommitment.seats[0].committedThisHand.rawValue + 1
    )!
    let wrongCommitmentSnapshot = wrongCommitment
    #expect(throws: PokerRuleError.invalidState("unallocated pot mismatch")) {
        try HoldemEngine.advanceIfRoundComplete(wrongCommitment)
    }
    #expect(wrongCommitment == wrongCommitmentSnapshot)

    var wrongActor = valid
    wrongActor.currentActor = nil
    let wrongActorSnapshot = wrongActor
    #expect(throws: PokerRuleError.invalidState("invalid actor")) {
        try HoldemEngine.advanceIfRoundComplete(wrongActor)
    }
    #expect(wrongActor == wrongActorSnapshot)

    var wrongAllIn = valid
    wrongAllIn.seats[0].isAllIn = true
    let wrongAllInSnapshot = wrongAllIn
    #expect(throws: PokerRuleError.invalidState("inconsistent all-in state")) {
        try HoldemEngine.advanceIfRoundComplete(wrongAllIn)
    }
    #expect(wrongAllIn == wrongAllInSnapshot)

    var wrongBringIn = valid
    wrongBringIn.forcedBringIn = Chips(rawValue: 50)!
    let wrongBringInSnapshot = wrongBringIn
    #expect(throws: PokerRuleError.invalidState("invalid forced bring-in")) {
        try HoldemEngine.advanceIfRoundComplete(wrongBringIn)
    }
    #expect(wrongBringIn == wrongBringInSnapshot)
}

@Test func streetsDealThreeThenOneThenOneAndActLeftOfDealer() throws {
    let completedPreflop = try Fixtures.completePreflopState()
    #expect(completedPreflop.street == .preflop)
    let flop = try HoldemEngine.advanceIfRoundComplete(completedPreflop)
    var state = flop.state
    #expect(state.street == .flop)
    #expect(state.communityCards.count == 3)
    #expect(state.currentActor == SeatID(rawValue: 1)!)
    #expect(state.seats.allSatisfy { $0.committedThisStreet == Chips(rawValue: 0)! })
    #expect(state.currentBet == Chips(rawValue: 0)!)
    #expect(state.forcedBringIn == Chips(rawValue: 0)!)
    #expect(state.lastFullRaiseSize == Chips(rawValue: 100)!)
    #expect(state.actedSinceLastFullRaise.isEmpty)
    #expect(state.lastActedAtBet.isEmpty)
    #expect(flop.events == [
        .streetChanged(.flop),
        .communityCardsDealt(state.communityCards),
    ])

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

@Test func nextActorSkipsFoldedAndAllInSeats() throws {
    var started = try HoldemEngine.start(
        config: Fixtures.standardConfig(dealer: 2),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 1)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 3)!: Chips(rawValue: 1_000)!,
        ],
        seed: 9
    ).state
    started.seats[2].hasFolded = true

    let folded = try HoldemEngine.applying(.fold, by: SeatID(1), to: started)

    #expect(folded.state.seats.first { $0.id == SeatID(rawValue: 0)! }?.isAllIn == true)
    #expect(folded.state.currentActor == SeatID(rawValue: 3)!)
}

@Test func nextActorSkipsSittingOutSeat() throws {
    var started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: stacks([0, 1, 2, 3], amount: 1_000),
        seed: 10
    ).state
    started.seats[0].isSittingOut = true

    let folded = try HoldemEngine.applying(.fold, by: SeatID(3), to: started)

    #expect(folded.state.currentActor == SeatID(rawValue: 1)!)
}

@Test func fullRaiseKeepsEveryUnmatchedSeatInTheRound() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: stacks([0, 1, 2], amount: 1_000),
        seed: 11
    )
    let raised = try HoldemEngine.applying(
        .raiseTo(Chips(rawValue: 300)!),
        by: SeatID(0),
        to: started.state
    )
    let smallBlindCalled = try HoldemEngine.applying(
        .call,
        by: SeatID(1),
        to: raised.state
    )

    #expect(smallBlindCalled.state.street == .preflop)
    #expect(smallBlindCalled.state.currentActor == SeatID(rawValue: 2)!)
    #expect(smallBlindCalled.events == [
        .actionApplied(seat: SeatID(rawValue: 1)!, action: .call),
    ])
}

@Test func shortAllInDoesNotEndRoundBeforeOtherSeatsRespond() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: [
            SeatID(rawValue: 0)!: Chips(rawValue: 150)!,
            SeatID(rawValue: 1)!: Chips(rawValue: 1_000)!,
            SeatID(rawValue: 2)!: Chips(rawValue: 1_000)!,
        ],
        seed: 12
    )

    let allIn = try HoldemEngine.applying(.allIn, by: SeatID(0), to: started.state)

    #expect(allIn.state.street == .preflop)
    #expect(allIn.state.currentBet == Chips(rawValue: 150)!)
    #expect(allIn.state.currentActor == SeatID(rawValue: 1)!)
    #expect(allIn.events == [
        .actionApplied(seat: SeatID(rawValue: 0)!, action: .allIn),
    ])
}

@Test func foldingToOneRemainingPlayerImmediatelyEntersShowdown() throws {
    let started = try HoldemEngine.start(
        config: standardConfig(),
        stacks: Fixtures.twoStacks(1_000),
        seed: 13
    )

    let folded = try HoldemEngine.applying(.fold, by: SeatID(0), to: started.state)

    #expect(folded.state.street == .showdown)
    #expect(folded.state.currentActor == nil)
    #expect(folded.state.forcedBringIn == Chips(rawValue: 0)!)
    #expect(folded.events == [
        .actionApplied(seat: SeatID(rawValue: 0)!, action: .fold),
        .streetChanged(.showdown),
    ])
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

@Test func lastRemainingPlayerWinsWithoutShowingOtherCards() throws {
    let result = try Fixtures.playUntilEveryoneButSeatZeroFolds()

    #expect(result.state.street == .complete)
    #expect(result.state.communityCards.isEmpty)
    #expect(result.state.awards == [SeatID(rawValue: 0)!: Chips(rawValue: 150)!])
    #expect(result.state.totalSeatChips == result.state.initialTotalChips)
    #expect(result.events.last == .handCompleted)
}

@Test func twoWayAllInAwardsMainPotByRankAndExcessOnlyToEligibleSeat() throws {
    let result = try Fixtures.resolveTwoWayAllInWithSidePot()
    let seatZero = SeatID(rawValue: 0)!
    let seatOne = SeatID(rawValue: 1)!
    let zeroState = try #require(result.state.seats.first { $0.id == seatZero })
    let oneState = try #require(result.state.seats.first { $0.id == seatOne })
    let zeroRank = try HandEvaluator.best(of: zeroState.holeCards + result.state.communityCards)
    let oneRank = try HandEvaluator.best(of: oneState.holeCards + result.state.communityCards)

    #expect(zeroRank > oneRank)
    #expect(result.state.settledPots == [
        Pot(amount: Chips(rawValue: 400)!, eligible: [seatZero, seatOne]),
        Pot(amount: Chips(rawValue: 100)!, eligible: [seatOne]),
    ])
    #expect(result.state.awards == [
        seatZero: Chips(rawValue: 400)!,
        seatOne: Chips(rawValue: 100)!,
    ])
}

@Test func showdownAwardsEverySidePotToBestEligibleHand() throws {
    let result = try Fixtures.resolveThreeWayAllInWithTwoSidePots()
    let seatZero = SeatID(rawValue: 0)!
    let seatOne = SeatID(rawValue: 1)!
    let seatTwo = SeatID(rawValue: 2)!
    let ranks = try Dictionary(uniqueKeysWithValues: result.state.seats.map {
        ($0.id, try HandEvaluator.best(of: $0.holeCards + result.state.communityCards))
    })

    #expect(ranks[seatZero]! > ranks[seatOne]!)
    #expect(ranks[seatOne]! > ranks[seatTwo]!)
    #expect(result.state.settledPots == [
        Pot(amount: Chips(rawValue: 300)!, eligible: [seatZero, seatOne, seatTwo]),
        Pot(amount: Chips(rawValue: 200)!, eligible: [seatOne, seatTwo]),
        Pot(amount: Chips(rawValue: 100)!, eligible: [seatTwo]),
    ])
    #expect(result.state.awards == [
        seatZero: Chips(rawValue: 300)!,
        seatOne: Chips(rawValue: 200)!,
        seatTwo: Chips(rawValue: 100)!,
    ])
    #expect(result.state.unallocatedPot.rawValue == 0)
    #expect(result.state.totalSeatChips == Fixtures.initialTotalChips)
}

@Test func exactTieSplitsOddChipLeftOfDealerAndPreservesTotalChips() throws {
    let result = try Fixtures.resolveBoardPlayingTie()
    let seatZero = SeatID(rawValue: 0)!
    let seatTwo = SeatID(rawValue: 2)!
    let boardRank = try HandEvaluator.best(of: result.state.communityCards)
    let activeRanks = try result.state.activeSeats.map {
        try HandEvaluator.best(of: $0.holeCards + result.state.communityCards)
    }
    let firstPotAward = try #require(result.events.first { event in
        guard case .potAwarded(potIndex: 0, winners: _, amounts: _) = event else {
            return false
        }
        return true
    })

    #expect(activeRanks.allSatisfy { $0 == boardRank })
    #expect(result.state.awards == [
        seatZero: Chips(rawValue: 2)!,
        seatTwo: Chips(rawValue: 3)!,
    ])
    #expect(result.state.totalSeatChips == result.state.initialTotalChips)
    #expect(result.state.street == .complete)
    #expect(result.state.awards[SeatID(rawValue: 1)!] == nil)
    #expect(firstPotAward == .potAwarded(
        potIndex: 0,
        winners: [seatTwo, seatZero],
        amounts: [seatTwo: Chips(rawValue: 2)!, seatZero: Chips(rawValue: 1)!]
    ))
}

@Test func potAwardEventsMatchSettledPotsInOrderAndAmount() throws {
    let result = try Fixtures.resolveThreeWayAllInWithTwoSidePots()
    let seatZero = SeatID(rawValue: 0)!
    let seatOne = SeatID(rawValue: 1)!
    let seatTwo = SeatID(rawValue: 2)!
    let pots = result.state.settledPots

    #expect(result.events == [
        .potCreated(pots[0]),
        .potCreated(pots[1]),
        .potCreated(pots[2]),
        .potAwarded(
            potIndex: 0,
            winners: [seatZero],
            amounts: [seatZero: Chips(rawValue: 300)!]
        ),
        .potAwarded(
            potIndex: 1,
            winners: [seatOne],
            amounts: [seatOne: Chips(rawValue: 200)!]
        ),
        .potAwarded(
            potIndex: 2,
            winners: [seatTwo],
            amounts: [seatTwo: Chips(rawValue: 100)!]
        ),
        .handCompleted,
    ])

    let eventAwards = try result.events.reduce(into: [SeatID: Chips]()) { awards, event in
        guard case let .potAwarded(_, _, amounts) = event else { return }
        for (seat, amount) in amounts {
            let (total, overflow) = (awards[seat]?.rawValue ?? 0)
                .addingReportingOverflow(amount.rawValue)
            guard !overflow else {
                throw PokerRuleError.invalidState("test award overflow")
            }
            awards[seat] = Chips(rawValue: total)!
        }
    }
    #expect(result.state.awards == eventAwards)
}

@Test func completionClearsLiveAccountingAndPreservesSettlementHistory() throws {
    let result = try Fixtures.resolveThreeWayAllInWithTwoSidePots()

    #expect(result.state.street == .complete)
    #expect(result.state.currentActor == nil)
    #expect(result.state.unallocatedPot == Chips(rawValue: 0)!)
    #expect(result.state.currentBet == Chips(rawValue: 0)!)
    #expect(result.state.seats.allSatisfy {
        $0.committedThisStreet == Chips(rawValue: 0)!
            && $0.committedThisHand == Chips(rawValue: 0)!
    })
    #expect(!result.state.settledPots.isEmpty)
    #expect(!result.state.awards.isEmpty)
    #expect(result.state.uncalledReturns.isEmpty)
    try BettingRules.validateStructuralState(result.state)
}

@Test func settlingCompletedHandIsIdempotentNoOp() throws {
    let completed = try Fixtures.resolveBoardPlayingTie().state

    let repeated = try HoldemEngine.advanceIfRoundComplete(completed)

    #expect(repeated == EngineResult(state: completed, events: []))
}

@Test func multiplayerShowdownRequiresFiveCommunityCardsWithoutMutation() throws {
    var showdown = try Fixtures.boardPlayingTieShowdown()
    showdown.communityCards.removeLast()
    let snapshot = showdown

    #expect(throws: PokerRuleError.invalidState("card count")) {
        try HoldemEngine.advanceIfRoundComplete(showdown)
    }
    #expect(showdown == snapshot)
}

@Test func evaluationFailureDoesNotPartiallyUpdateSettlement() throws {
    var showdown = try Fixtures.boardPlayingTieShowdown()
    showdown.communityCards[4] = showdown.communityCards[3]
    let snapshot = showdown

    #expect(throws: PokerRuleError.invalidState("duplicate cards")) {
        try HoldemEngine.advanceIfRoundComplete(showdown)
    }
    #expect(showdown == snapshot)
    #expect(showdown.settledPots.isEmpty)
    #expect(showdown.awards.isEmpty)
}
