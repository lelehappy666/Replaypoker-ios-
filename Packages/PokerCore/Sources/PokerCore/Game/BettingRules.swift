public enum BettingRules {
    public static func legalActions(
        for seat: SeatID,
        in state: HoldemState
    ) throws -> LegalActionSet {
        guard state.currentActor == seat else {
            throw PokerRuleError.illegalAction("not current actor")
        }
        guard let seatState = state.seats.first(where: { $0.id == seat }),
              state.canAct(seat) else {
            throw PokerRuleError.illegalAction("seat cannot act")
        }
        guard state.currentBet.rawValue >= seatState.committedThisStreet.rawValue else {
            throw PokerRuleError.invalidState("commitment exceeds current bet")
        }

        let amountToCall = state.currentBet.rawValue - seatState.committedThisStreet.rawValue
        let maximumTo = seatState.committedThisStreet.rawValue + seatState.stack.rawValue
        let raisingIsOpen = !state.actedSinceLastFullRaise.contains(seat)
        let minimumRaiseToValue = state.currentBet.rawValue + state.lastFullRaiseSize.rawValue

        let minimumBet = state.currentBet.rawValue == 0
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
            commit(callAmount.rawValue, forSeatAt: seatIndex, in: &result)
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
            commit(contribution, forSeatAt: seatIndex, in: &result)
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
            commit(contribution, forSeatAt: seatIndex, in: &result)
            result.currentBet = amount
            result.lastFullRaiseSize = Chips(rawValue: raiseSize)!
            result.actedSinceLastFullRaise = [seat]

        case .allIn:
            guard legal.canAllIn else {
                throw PokerRuleError.illegalAction("cannot all in")
            }
            let contribution = result.seats[seatIndex].stack.rawValue
            let allInTo = result.seats[seatIndex].committedThisStreet.rawValue + contribution
            commit(contribution, forSeatAt: seatIndex, in: &result)

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

        result.actionHistory.append(
            RecordedAction(seat: seat, street: state.street, action: action)
        )
        return result
    }

    private static func commit(
        _ amount: Int,
        forSeatAt seatIndex: Int,
        in state: inout HoldemState
    ) {
        let seat = state.seats[seatIndex]
        state.seats[seatIndex].stack = Chips(rawValue: seat.stack.rawValue - amount)!
        state.seats[seatIndex].committedThisStreet = Chips(
            rawValue: seat.committedThisStreet.rawValue + amount
        )!
        state.seats[seatIndex].committedThisHand = Chips(
            rawValue: seat.committedThisHand.rawValue + amount
        )!
        state.unallocatedPot = Chips(rawValue: state.unallocatedPot.rawValue + amount)!
        state.seats[seatIndex].isAllIn = state.seats[seatIndex].stack.rawValue == 0
    }
}
