import Testing
@testable import PokerCore

@Test func unopenedPotAllowsCheckOrBet() throws {
    let state = Fixtures.bettingState(
        currentBet: 0,
        seatCommitment: 0,
        stack: 1_000,
        lastFullRaise: 100
    )

    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)

    #expect(legal.canFold == false)
    #expect(legal.canCheck)
    #expect(legal.callAmount == nil)
    #expect(legal.minimumBet == Chips(rawValue: 100)!)
    #expect(legal.minimumRaiseTo == nil)
    #expect(legal.maximumRaiseTo == Chips(rawValue: 1_000)!)
    #expect(legal.canAllIn)
}

@Test func facingBetAllowsFoldCallAndFullRaise() throws {
    let state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )

    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)

    #expect(legal.canFold)
    #expect(legal.canCheck == false)
    #expect(legal.callAmount == Chips(rawValue: 200)!)
    #expect(legal.minimumBet == nil)
    #expect(legal.minimumRaiseTo == Chips(rawValue: 500)!)
    #expect(legal.maximumRaiseTo == Chips(rawValue: 1_100)!)
}

@Test func stackSmallerThanCallCanCallAllIn() throws {
    let state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 80,
        lastFullRaise: 200
    )

    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)
    let result = try BettingRules.applying(.call, by: SeatID(0), to: state)
    let seat = try #require(result.seats.first { $0.id == SeatID(rawValue: 0)! })

    #expect(legal.callAmount == Chips(rawValue: 80)!)
    #expect(legal.canRaise == false)
    #expect(seat.stack == Chips(rawValue: 0)!)
    #expect(seat.committedThisStreet == Chips(rawValue: 180)!)
    #expect(seat.committedThisHand == Chips(rawValue: 180)!)
    #expect(seat.isAllIn)
}

@Test func maximumRaiseToIncludesStreetCommitmentAndStack() throws {
    let state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )

    let legal = try BettingRules.legalActions(for: SeatID(0), in: state)

    #expect(legal.maximumRaiseTo == Chips(rawValue: 1_100)!)
}

@Test func belowMinimumBetOrRaiseIsRejectedUnlessAllIn() throws {
    let unopened = Fixtures.bettingState(
        currentBet: 0,
        seatCommitment: 0,
        stack: 1_000,
        lastFullRaise: 100
    )
    let facingBet = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )

    #expect(throws: PokerRuleError.illegalAction("bet below minimum")) {
        try BettingRules.applying(.bet(Chips(rawValue: 99)!), by: SeatID(0), to: unopened)
    }
    #expect(throws: PokerRuleError.illegalAction("raise below minimum")) {
        try BettingRules.applying(.raiseTo(Chips(rawValue: 499)!), by: SeatID(0), to: facingBet)
    }
}

@Test func shortAllInIsAcceptedWithoutReopeningRaising() throws {
    var state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )
    state.currentActor = SeatID(rawValue: 2)!
    state.actedSinceLastFullRaise = [SeatID(rawValue: 0)!]

    state.seats[2].stack = Chips(rawValue: 50)!
    state.seats[3].stack = Chips(rawValue: 1_650)!
    let result = try BettingRules.applying(.allIn, by: SeatID(2), to: state)
    var returned = result
    returned.currentActor = SeatID(rawValue: 0)!
    let seatTwo = try #require(result.seats.first { $0.id == SeatID(rawValue: 2)! })
    let legal = try BettingRules.legalActions(for: SeatID(0), in: returned)

    #expect(result.currentBet == Chips(rawValue: 350)!)
    #expect(result.lastFullRaiseSize == Chips(rawValue: 200)!)
    #expect(result.actedSinceLastFullRaise == [SeatID(rawValue: 0)!, SeatID(rawValue: 2)!])
    #expect(seatTwo.stack == Chips(rawValue: 0)!)
    #expect(seatTwo.committedThisStreet == Chips(rawValue: 350)!)
    #expect(legal.callAmount == Chips(rawValue: 250)!)
    #expect(legal.canRaise == false)
}

@Test func shortAllInFixtureDoesNotReopenRaising() throws {
    let state = Fixtures.shortAllInAfterFullRaise()

    #expect(try BettingRules.legalActions(for: SeatID(0), in: state).canRaise == false)
}

@Test func fullRaiseUpdatesMinimumAndReopensRaising() throws {
    var state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )
    state.currentActor = SeatID(rawValue: 1)!
    state.actedSinceLastFullRaise = [SeatID(rawValue: 0)!, SeatID(rawValue: 2)!]
    state.seats[1].committedThisStreet = Chips(rawValue: 100)!
    state.seats[1].committedThisHand = Chips(rawValue: 100)!
    state.seats[1].stack = Chips(rawValue: 900)!
    state.unallocatedPot = Chips(rawValue: 500)!

    let result = try BettingRules.applying(
        .raiseTo(Chips(rawValue: 600)!),
        by: SeatID(1),
        to: state
    )
    var returned = result
    returned.currentActor = SeatID(rawValue: 0)!
    let legal = try BettingRules.legalActions(for: SeatID(0), in: returned)

    #expect(result.currentBet == Chips(rawValue: 600)!)
    #expect(result.lastFullRaiseSize == Chips(rawValue: 300)!)
    #expect(result.actedSinceLastFullRaise == [SeatID(rawValue: 1)!])
    #expect(legal.minimumRaiseTo == Chips(rawValue: 900)!)
    #expect(result.totalSeatChips + result.unallocatedPot.rawValue == result.initialTotalChips)
}

@Test func appliesCheckFoldBetAndRaiseWithChipConservation() throws {
    let unopened = Fixtures.bettingState(
        currentBet: 0,
        seatCommitment: 0,
        stack: 1_000,
        lastFullRaise: 100
    )
    let checked = try BettingRules.applying(.check, by: SeatID(0), to: unopened)
    let foldedState = Fixtures.bettingState(
        currentBet: 100,
        seatCommitment: 0,
        stack: 1_000,
        lastFullRaise: 100
    )
    let folded = try BettingRules.applying(.fold, by: SeatID(0), to: foldedState)
    let bet = try BettingRules.applying(
        .bet(Chips(rawValue: 250)!),
        by: SeatID(0),
        to: unopened
    )
    let raisedState = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )
    let raised = try BettingRules.applying(
        .raiseTo(Chips(rawValue: 500)!),
        by: SeatID(0),
        to: raisedState
    )

    #expect(checked.actedSinceLastFullRaise.contains(SeatID(rawValue: 0)!))
    #expect(folded.seats[0].hasFolded)
    #expect(bet.currentBet == Chips(rawValue: 250)!)
    #expect(bet.seats[0].stack == Chips(rawValue: 750)!)
    #expect(bet.seats[0].committedThisStreet == Chips(rawValue: 250)!)
    #expect(raised.seats[0].stack == Chips(rawValue: 600)!)
    #expect(raised.seats[0].committedThisStreet == Chips(rawValue: 500)!)
    #expect(chipTotal(bet) == bet.initialTotalChips)
    #expect(chipTotal(raised) == raised.initialTotalChips)
    #expect(bet.totalSeatChips + bet.unallocatedPot.rawValue == bet.initialTotalChips)
    #expect(raised.totalSeatChips + raised.unallocatedPot.rawValue == raised.initialTotalChips)
    #expect(raised.actionHistory.last == RecordedAction(
        seat: SeatID(rawValue: 0)!,
        street: .flop,
        action: .raiseTo(Chips(rawValue: 500)!)
    ))
}

@Test func wrongActorFoldedAndAllInSeatsAreRejected() throws {
    let state = Fixtures.bettingState(
        currentBet: 100,
        seatCommitment: 0,
        stack: 1_000,
        lastFullRaise: 100
    )
    var folded = state
    folded.seats[0].hasFolded = true
    var allIn = state
    allIn.seats[0].isAllIn = true

    #expect(throws: PokerRuleError.illegalAction("not current actor")) {
        try BettingRules.legalActions(for: SeatID(1), in: state)
    }
    #expect(throws: PokerRuleError.illegalAction("seat cannot act")) {
        try BettingRules.legalActions(for: SeatID(0), in: folded)
    }
    #expect(throws: PokerRuleError.illegalAction("seat cannot act")) {
        try BettingRules.applying(.call, by: SeatID(0), to: allIn)
    }
}

@Test func illegalActionsDoNotMutateInputState() throws {
    let state = Fixtures.bettingState(
        currentBet: 300,
        seatCommitment: 100,
        stack: 1_000,
        lastFullRaise: 200
    )
    let snapshot = state

    #expect(throws: PokerRuleError.illegalAction("raise below minimum")) {
        try BettingRules.applying(.raiseTo(Chips(rawValue: 499)!), by: SeatID(0), to: state)
    }
    #expect(state == snapshot)
}

@Test func handConfigRejectsInvalidBlinds() {
    #expect(throws: PokerRuleError.invalidState("invalid blinds")) {
        try HandConfig(
            smallBlind: Chips(rawValue: 0)!,
            bigBlind: Chips(rawValue: 100)!,
            dealer: SeatID(rawValue: 8)!
        )
    }
    #expect(throws: PokerRuleError.invalidState("invalid blinds")) {
        try HandConfig(
            smallBlind: Chips(rawValue: 50)!,
            bigBlind: Chips(rawValue: 99)!,
            dealer: SeatID(rawValue: 8)!
        )
    }
}

private func chipTotal(_ state: HoldemState) -> Int {
    state.seats.reduce(0) { partial, seat in
        partial + seat.stack.rawValue + seat.committedThisHand.rawValue
    }
}
