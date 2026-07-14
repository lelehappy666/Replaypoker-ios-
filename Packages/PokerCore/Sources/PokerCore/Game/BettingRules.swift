public enum BettingRules {
    public static func legalActions(
        for seat: SeatID,
        in state: HoldemState
    ) throws -> LegalActionSet {
        try validateActionState(state)
        guard state.currentActor == seat else {
            throw PokerRuleError.illegalAction("not current actor")
        }
        guard let seatState = state.seats.first(where: { $0.id == seat }) else {
            throw PokerRuleError.invalidState("invalid actor")
        }

        let amountToCall = state.currentBet.rawValue - seatState.committedThisStreet.rawValue
        let maximumTo = try checkedAdd(
            seatState.committedThisStreet.rawValue,
            seatState.stack.rawValue
        )
        let minimumRaiseToValue = try checkedAdd(
            state.currentBet.rawValue,
            state.lastFullRaiseSize.rawValue
        )
        let raisingIsOpen: Bool
        if let lastActedAt = state.lastActedAtBet[seat] {
            raisingIsOpen = state.currentBet.rawValue - lastActedAt.rawValue
                >= state.lastFullRaiseSize.rawValue
        } else {
            raisingIsOpen = true
        }

        let minimumBet = state.currentBet.rawValue == 0
            && raisingIsOpen
            && maximumTo >= state.lastFullRaiseSize.rawValue
            ? state.lastFullRaiseSize
            : nil
        let minimumRaiseTo = state.currentBet.rawValue > 0
            && raisingIsOpen
            && maximumTo >= minimumRaiseToValue
            ? Chips(rawValue: minimumRaiseToValue)
            : nil
        let canAllIn = seatState.stack.rawValue > 0
            && (maximumTo <= state.currentBet.rawValue || raisingIsOpen)

        return LegalActionSet(
            canFold: amountToCall > 0,
            canCheck: amountToCall == 0,
            callAmount: amountToCall > 0
                ? Chips(rawValue: min(amountToCall, seatState.stack.rawValue))
                : nil,
            minimumBet: minimumBet,
            minimumRaiseTo: minimumRaiseTo,
            maximumRaiseTo: seatState.stack.rawValue > 0 ? Chips(rawValue: maximumTo) : nil,
            canAllIn: canAllIn
        )
    }

    public static func applying(
        _ action: PlayerAction,
        by seat: SeatID,
        to state: HoldemState
    ) throws -> HoldemState {
        let legal = try legalActions(for: seat, in: state)
        guard let seatIndex = state.seats.firstIndex(where: { $0.id == seat }) else {
            throw PokerRuleError.illegalAction("seat cannot act")
        }

        var result = state

        switch action {
        case .fold:
            guard legal.canFold else {
                throw PokerRuleError.illegalAction("cannot fold")
            }
            result.seats[seatIndex].hasFolded = true
            result.actedSinceLastFullRaise.insert(seat)

        case .check:
            guard legal.canCheck else {
                throw PokerRuleError.illegalAction("cannot check")
            }
            result.actedSinceLastFullRaise.insert(seat)

        case .call:
            guard let callAmount = legal.callAmount else {
                throw PokerRuleError.illegalAction("cannot call")
            }
            try commit(callAmount.rawValue, forSeatAt: seatIndex, in: &result)
            result.actedSinceLastFullRaise.insert(seat)

        case let .bet(amount):
            guard state.currentBet.rawValue == 0 else {
                throw PokerRuleError.illegalAction("cannot bet facing bet")
            }
            guard let minimumBet = legal.minimumBet,
                  amount.rawValue >= minimumBet.rawValue else {
                throw PokerRuleError.illegalAction("bet below minimum")
            }
            guard let maximumTo = legal.maximumRaiseTo,
                  amount.rawValue <= maximumTo.rawValue else {
                throw PokerRuleError.illegalAction("bet exceeds stack")
            }
            let contribution = amount.rawValue - result.seats[seatIndex].committedThisStreet.rawValue
            try commit(contribution, forSeatAt: seatIndex, in: &result)
            result.currentBet = amount
            result.lastFullRaiseSize = amount
            result.actedSinceLastFullRaise = [seat]

        case let .raiseTo(amount):
            guard state.currentBet.rawValue > 0 else {
                throw PokerRuleError.illegalAction("cannot raise unopened pot")
            }
            guard let minimumRaiseTo = legal.minimumRaiseTo,
                  amount.rawValue >= minimumRaiseTo.rawValue else {
                throw PokerRuleError.illegalAction("raise below minimum")
            }
            guard let maximumTo = legal.maximumRaiseTo,
                  amount.rawValue <= maximumTo.rawValue else {
                throw PokerRuleError.illegalAction("raise exceeds stack")
            }
            let contribution = amount.rawValue - result.seats[seatIndex].committedThisStreet.rawValue
            let raiseSize = amount.rawValue - state.currentBet.rawValue
            try commit(contribution, forSeatAt: seatIndex, in: &result)
            result.currentBet = amount
            result.lastFullRaiseSize = Chips(rawValue: raiseSize)!
            result.actedSinceLastFullRaise = [seat]

        case .allIn:
            guard legal.canAllIn else {
                throw PokerRuleError.illegalAction("cannot all in")
            }
            let contribution = result.seats[seatIndex].stack.rawValue
            let allInTo = try checkedAdd(
                result.seats[seatIndex].committedThisStreet.rawValue,
                contribution
            )
            try commit(contribution, forSeatAt: seatIndex, in: &result)

            if allInTo > state.currentBet.rawValue {
                let raiseSize = allInTo - state.currentBet.rawValue
                result.currentBet = Chips(rawValue: allInTo)!
                if raiseSize >= state.lastFullRaiseSize.rawValue {
                    result.lastFullRaiseSize = Chips(rawValue: raiseSize)!
                    result.actedSinceLastFullRaise = [seat]
                } else {
                    result.actedSinceLastFullRaise.insert(seat)
                }
            } else {
                result.actedSinceLastFullRaise.insert(seat)
            }
        }

        result.lastActedAtBet[seat] = result.currentBet
        result.actionHistory.append(
            RecordedAction(seat: seat, street: state.street, action: action)
        )
        return result
    }

    private static func commit(
        _ amount: Int,
        forSeatAt seatIndex: Int,
        in state: inout HoldemState
    ) throws {
        let seat = state.seats[seatIndex]
        guard amount >= 0, amount <= seat.stack.rawValue else {
            throw PokerRuleError.invalidState("invalid chip commitment")
        }
        let streetCommitment = try checkedAdd(seat.committedThisStreet.rawValue, amount)
        let handCommitment = try checkedAdd(seat.committedThisHand.rawValue, amount)
        let unallocatedPot = try checkedAdd(state.unallocatedPot.rawValue, amount)

        state.seats[seatIndex].stack = Chips(rawValue: seat.stack.rawValue - amount)!
        state.seats[seatIndex].committedThisStreet = Chips(rawValue: streetCommitment)!
        state.seats[seatIndex].committedThisHand = Chips(rawValue: handCommitment)!
        state.unallocatedPot = Chips(rawValue: unallocatedPot)!
        state.seats[seatIndex].isAllIn = state.seats[seatIndex].stack.rawValue == 0
    }

    static func validateStructuralState(_ state: HoldemState) throws {
        guard Set(state.seats.map(\.id)).count == state.seats.count else {
            throw PokerRuleError.invalidState("duplicate seat ids")
        }
        guard state.seats.allSatisfy({ ($0.stack.rawValue == 0) == $0.isAllIn }) else {
            throw PokerRuleError.invalidState("inconsistent all-in state")
        }
        guard state.lastFullRaiseSize.rawValue > 0 else {
            throw PokerRuleError.invalidState("invalid last full raise")
        }
        guard state.seats.allSatisfy({
            $0.committedThisHand.rawValue >= $0.committedThisStreet.rawValue
        }) else {
            throw PokerRuleError.invalidState("hand commitment below street commitment")
        }
        if state.street == .preflop {
            guard state.forcedBringIn == state.config.bigBlind else {
                throw PokerRuleError.invalidState("invalid forced bring-in")
            }
        } else {
            guard state.forcedBringIn.rawValue == 0 else {
                throw PokerRuleError.invalidState("forced bring-in outside preflop")
            }
        }
        let maximumCommitment = state.seats.map(\.committedThisStreet.rawValue).max() ?? 0
        let effectiveMaximum = max(maximumCommitment, state.forcedBringIn.rawValue)
        guard state.currentBet.rawValue == effectiveMaximum else {
            throw PokerRuleError.invalidState("current bet mismatch")
        }
        let knownSeats = Set(state.seats.map(\.id))
        guard state.actedSinceLastFullRaise.isSubset(of: knownSeats) else {
            throw PokerRuleError.invalidState("unknown acted seat")
        }
        guard state.actedSinceLastFullRaise.allSatisfy({ state.lastActedAtBet[$0] != nil }) else {
            throw PokerRuleError.invalidState("acted seat missing baseline")
        }
        guard state.lastActedAtBet.allSatisfy({ seat, amount in
            knownSeats.contains(seat)
                && amount.rawValue <= state.currentBet.rawValue
        }) else {
            throw PokerRuleError.invalidState("invalid action baseline")
        }
        guard state.lastActedAtBet.allSatisfy({ seat, amount in
            guard let seatState = state.seats.first(where: { $0.id == seat }) else {
                return false
            }
            return !state.canAct(seat)
                || amount.rawValue == seatState.committedThisStreet.rawValue
        }) else {
            throw PokerRuleError.invalidState("action baseline commitment mismatch")
        }

        var totalCommitments = 0
        for seat in state.seats {
            totalCommitments = try checkedAdd(
                totalCommitments,
                seat.committedThisHand.rawValue
            )
        }
        guard totalCommitments == state.unallocatedPot.rawValue else {
            throw PokerRuleError.invalidState("unallocated pot mismatch")
        }

        let totalSeatChips = try state.validatedTotalSeatChips()
        let accountedChips = try checkedAdd(totalSeatChips, state.unallocatedPot.rawValue)
        guard accountedChips == state.initialTotalChips else {
            throw PokerRuleError.invalidState("chip conservation")
        }
        let isBettingStreet = [.preflop, .flop, .turn, .river].contains(state.street)
        if isBettingStreet {
            let actionableSeats = state.seats.filter { state.canAct($0.id) }
            if actionableSeats.isEmpty {
                guard state.currentActor == nil else {
                    throw PokerRuleError.invalidState("invalid actor")
                }
            } else {
                guard let actor = state.currentActor, state.canAct(actor) else {
                    throw PokerRuleError.invalidState("invalid actor")
                }
            }
        } else {
            guard state.currentActor == nil else {
                throw PokerRuleError.invalidState("invalid actor")
            }
        }
    }

    private static func validateActionState(_ state: HoldemState) throws {
        try validateStructuralState(state)
        guard [.preflop, .flop, .turn, .river].contains(state.street),
              let actor = state.currentActor,
              state.canAct(actor) else {
            throw PokerRuleError.invalidState("invalid actor")
        }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw PokerRuleError.invalidState("chip arithmetic overflow")
        }
        return value
    }
}
