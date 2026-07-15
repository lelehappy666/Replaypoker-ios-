import PokerCore

struct CashTableAnimationSnapshot {
    let commitments: [SeatID: Chips]
    let stacks: [SeatID: Chips]
    let currentBet: Chips
}

enum CashTableAnimationMapper {
    static func map(
        _ events: [PublicGameEvent],
        humanSeat: SeatID,
        humanCards: [TableCardState],
        beforeAction: CashTableAnimationSnapshot?
    ) throws -> [TableAnimationEvent] {
        let humanDealCount = events.reduce(into: 0) { count, event in
            if case .holeCardsDealt(let seat) = event, seat == humanSeat {
                count += 1
            }
        }
        if humanDealCount > 0 {
            guard humanDealCount == 2,
                  humanCards.count == 2,
                  humanCards.allSatisfy({ card in
                      if case .faceUp = card { return true }
                      return false
                  })
            else {
                throw PokerCoordinatorError.missingObservation
            }
        }

        var nextHumanCard = humanCards
        var mapped: [TableAnimationEvent] = []

        for event in events {
            switch event {
            case .handStarted, .potCreated, .handCompleted:
                break
            case let .holeCardsDealt(seat):
                let card: TableCardState
                if seat == humanSeat {
                    guard !nextHumanCard.isEmpty else {
                        throw PokerCoordinatorError.missingObservation
                    }
                    card = nextHumanCard.removeFirst()
                } else {
                    card = .faceDown
                }
                mapped.append(.dealHoleCard(seat: seat, card: card))
            case let .blindPosted(seat, amount):
                mapped.append(.postBlind(seat: seat, amount: amount))
            case let .actionApplied(seat, action):
                mapped.append(.showAction(seat: seat, action: action))
                let amount = try contribution(
                    for: action,
                    by: seat,
                    before: beforeAction
                )
                if amount.rawValue > 0 {
                    mapped.append(.moveCommitmentToPot(seat: seat, amount: amount))
                }
            case let .streetChanged(street):
                mapped.append(.streetChanged(street))
            case let .communityCardsDealt(cards):
                mapped.append(contentsOf: cards.enumerated().map {
                    .revealCommunityCard(card: $0.element, index: $0.offset)
                })
            case let .uncalledBetReturned(seat, amount):
                mapped.append(.returnUncalledBet(seat: seat, amount: amount))
            case let .potAwarded(index, _, amounts):
                for seat in amounts.keys.sorted() {
                    guard let amount = amounts[seat] else { continue }
                    mapped.append(.awardPot(seat: seat, amount: amount, potIndex: index))
                    mapped.append(.highlightWinner(seat))
                }
            }
        }
        return mapped
    }

    private static func contribution(
        for action: PlayerAction,
        by seat: SeatID,
        before snapshot: CashTableAnimationSnapshot?
    ) throws -> Chips {
        guard let snapshot,
              let committed = snapshot.commitments[seat],
              let stack = snapshot.stacks[seat]
        else {
            throw PokerCoordinatorError.missingObservation
        }
        let rawContribution: Int
        switch action {
        case .fold, .check:
            rawContribution = 0
        case .call:
            let (difference, overflow) = snapshot.currentBet.rawValue
                .subtractingReportingOverflow(committed.rawValue)
            guard !overflow, difference >= 0 else {
                throw PokerCoordinatorError.chipArithmeticOverflow
            }
            rawContribution = min(difference, stack.rawValue)
        case let .bet(amount), let .raiseTo(amount):
            let (difference, overflow) = amount.rawValue
                .subtractingReportingOverflow(committed.rawValue)
            guard !overflow, difference >= 0 else {
                throw PokerCoordinatorError.chipArithmeticOverflow
            }
            rawContribution = difference
        case .allIn:
            rawContribution = stack.rawValue
        }
        guard let contribution = Chips(rawValue: rawContribution) else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        return contribution
    }
}
