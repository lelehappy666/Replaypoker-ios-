public enum StateValidator {
    public static func validate(_ state: HoldemState) throws {
        try BettingRules.validateStructuralState(state)

        let allCards = state.seats.flatMap(\.holeCards)
            + state.communityCards
            + state.deck.remainingCards
        guard allCards.count == Card.fullDeck.count else {
            throw PokerRuleError.invalidState("card count")
        }
        guard Set(allCards).count == Card.fullDeck.count else {
            throw PokerRuleError.invalidState("duplicate cards")
        }
        guard state.seats.allSatisfy({ $0.holeCards.count == 2 }) else {
            throw PokerRuleError.invalidState("invalid hole cards")
        }

        let validCommunityCardCount: Bool
        switch state.street {
        case .preflop:
            validCommunityCardCount = state.communityCards.isEmpty
        case .flop:
            validCommunityCardCount = state.communityCards.count == 3
        case .turn:
            validCommunityCardCount = state.communityCards.count == 4
        case .river:
            validCommunityCardCount = state.communityCards.count == 5
        case .showdown, .complete:
            validCommunityCardCount = state.activeSeats.count > 1
                ? state.communityCards.count == 5
                : [0, 3, 4, 5].contains(state.communityCards.count)
        }
        guard validCommunityCardCount else {
            throw PokerRuleError.invalidState("invalid community card count")
        }

        let knownSeats = Set(state.seats.map(\.id))
        guard state.seats.count >= 2,
              state.seats.count <= 9,
              knownSeats.contains(state.dealer),
              knownSeats.contains(state.smallBlindSeat),
              knownSeats.contains(state.bigBlindSeat),
              state.config.dealer == state.dealer else {
            throw PokerRuleError.invalidState("invalid dealt seats")
        }
        guard Set(state.startingStacks.keys) == knownSeats else {
            throw PokerRuleError.invalidState("invalid starting stacks")
        }
        let startingTotal = try checkedSum(state.startingStacks.values.map(\.rawValue))
        guard startingTotal == state.initialTotalChips else {
            throw PokerRuleError.invalidState("invalid starting stacks")
        }
        let orderedSeats = knownSeats.sorted()
        let expectedSmallBlind = state.seats.count == 2
            ? state.dealer
            : nextSeat(after: state.dealer, among: orderedSeats)
        let expectedBigBlind = nextSeat(after: expectedSmallBlind, among: orderedSeats)
        guard state.smallBlindSeat == expectedSmallBlind,
              state.bigBlindSeat == expectedBigBlind,
              state.smallBlindSeat != state.bigBlindSeat else {
            throw PokerRuleError.invalidState("invalid blind seats")
        }

        if state.street == .complete {
            try validateCompletedState(state, knownSeats: knownSeats)
        } else {
            for seat in state.seats {
                let liveTotal = try checkedSum([
                    seat.stack.rawValue,
                    seat.committedThisHand.rawValue,
                ])
                guard liveTotal == state.startingStacks[seat.id]!.rawValue else {
                    throw PokerRuleError.invalidState("live stack mismatch")
                }
            }
            guard state.settledPots.isEmpty,
                  state.awards.isEmpty,
                  state.uncalledReturns.isEmpty,
                  state.settledCommitments.isEmpty,
                  state.settledContributions.isEmpty else {
                throw PokerRuleError.invalidState("premature settlement")
            }
        }
    }

    private static func validateCompletedState(
        _ state: HoldemState,
        knownSeats: Set<SeatID>
    ) throws {
        guard state.currentActor == nil,
              state.currentBet.rawValue == 0,
              state.forcedBringIn.rawValue == 0,
              state.unallocatedPot.rawValue == 0,
              state.actedSinceLastFullRaise.isEmpty,
              state.lastActedAtBet.isEmpty,
              state.seats.allSatisfy({
                  $0.committedThisStreet.rawValue == 0
                      && $0.committedThisHand.rawValue == 0
              }) else {
            throw PokerRuleError.invalidState("terminal commitments")
        }

        let activeSeats = Set(state.activeSeats.map(\.id))
        guard Set(state.settledCommitments.keys) == knownSeats,
              Set(state.settledContributions.keys) == knownSeats else {
            throw PokerRuleError.invalidState("settlement source mismatch")
        }
        guard state.settledPots.allSatisfy({ pot in
                  pot.amount.rawValue > 0
                      && !pot.eligible.isEmpty
                      && pot.eligible.isSubset(of: activeSeats)
              }),
              state.awards.allSatisfy({ knownSeats.contains($0.key) && $0.value.rawValue > 0 }),
              state.uncalledReturns.allSatisfy({
                  knownSeats.contains($0.key) && $0.value.rawValue > 0
              }) else {
            throw PokerRuleError.invalidState("settlement accounting")
        }
        let eligibleSeats = state.settledPots.reduce(into: Set<SeatID>()) {
            $0.formUnion($1.eligible)
        }
        guard Set(state.awards.keys).isSubset(of: eligibleSeats) else {
            throw PokerRuleError.invalidState("ineligible award")
        }

        var expectedReturns: [SeatID: Chips] = [:]
        for seat in knownSeats {
            let original = state.settledCommitments[seat]!.rawValue
            let normalized = state.settledContributions[seat]!.rawValue
            guard normalized <= original else {
                throw PokerRuleError.invalidState("settlement contribution mismatch")
            }
            let amount = original - normalized
            if amount > 0 {
                expectedReturns[seat] = Chips(rawValue: amount)!
            }
        }
        guard expectedReturns == state.uncalledReturns else {
            throw PokerRuleError.invalidState("settlement return mismatch")
        }

        let normalizedTotal = try checkedSum(
            state.settledContributions.values.map(\.rawValue)
        )
        let originalTotal = try checkedSum(state.settledCommitments.values.map(\.rawValue))
        let returnTotal = try checkedSum(state.uncalledReturns.values.map(\.rawValue))
        let potTotal = try checkedSum(state.settledPots.map { $0.amount.rawValue })
        let accountedOriginalTotal = try checkedSum([potTotal, returnTotal])
        guard normalizedTotal == potTotal,
              originalTotal == accountedOriginalTotal else {
            throw PokerRuleError.invalidState("settlement contribution mismatch")
        }
        let rebuiltPots = try PotBuilder.build(
            commitments: state.settledContributions,
            folded: state.foldedSeats
        )
        guard rebuiltPots == state.settledPots else {
            throw PokerRuleError.invalidState("settlement contribution mismatch")
        }

        let awardTotal = try checkedSum(state.awards.values.map(\.rawValue))
        guard potTotal == awardTotal else {
            throw PokerRuleError.invalidState("settlement accounting")
        }

        let ranks: [SeatID: HandRank]
        if state.activeSeats.count == 1 {
            ranks = [
                state.activeSeats[0].id: HandRank(category: .highCard, tieBreak: []),
            ]
        } else {
            ranks = try Dictionary(uniqueKeysWithValues: state.activeSeats.map { seat in
                (
                    seat.id,
                    try HandEvaluator.best(of: seat.holeCards + state.communityCards)
                )
            })
        }
        var expectedAwards: [SeatID: Int] = [:]
        for pot in state.settledPots {
            for (seat, amount) in try PotBuilder.awards(
                for: [pot],
                ranks: ranks,
                dealer: state.dealer
            ) {
                let total = try checkedSum([expectedAwards[seat, default: 0], amount.rawValue])
                expectedAwards[seat] = total
            }
        }
        guard expectedAwards == state.awards.mapValues(\.rawValue) else {
            throw PokerRuleError.invalidState("settlement awards mismatch")
        }

        for seat in state.seats {
            let starting = state.startingStacks[seat.id]!.rawValue
            let original = state.settledCommitments[seat.id]!.rawValue
            guard original <= starting else {
                throw PokerRuleError.invalidState("settlement stack mismatch")
            }
            let afterCommitment = starting - original
            let returned = state.uncalledReturns[seat.id]?.rawValue ?? 0
            let awarded = state.awards[seat.id]?.rawValue ?? 0
            let expectedStack = try checkedSum([afterCommitment, returned, awarded])
            guard expectedStack == seat.stack.rawValue else {
                throw PokerRuleError.invalidState("settlement stack mismatch")
            }
        }
    }

    private static func checkedSum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            guard !overflow else {
                throw PokerRuleError.invalidState("chip arithmetic overflow")
            }
            return result
        }
    }

    private static func nextSeat(after anchor: SeatID, among ids: [SeatID]) -> SeatID {
        ids.min {
            clockwiseDistance(from: anchor, to: $0)
                < clockwiseDistance(from: anchor, to: $1)
        }!
    }

    private static func clockwiseDistance(from anchor: SeatID, to id: SeatID) -> Int {
        let distance = (id.rawValue - anchor.rawValue + 9) % 9
        return distance == 0 ? 9 : distance
    }
}
