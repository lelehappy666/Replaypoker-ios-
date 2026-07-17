import PokerCore

struct CashTableAnimationSnapshot {
    let commitments: [SeatID: Chips]
    let stacks: [SeatID: Chips]
    let currentBet: Chips
}

enum CashTableAnimationMapper {
    static func completeWinnerSeats(in events: [PublicGameEvent]) -> Set<SeatID> {
        events.reduce(into: Set<SeatID>()) { winners, event in
            if case let .potAwarded(_, seats, _) = event {
                winners.formUnion(seats)
            }
        }
    }

    static func map(
        _ events: [PublicGameEvent],
        humanSeat: SeatID,
        humanCards: [TableCardState],
        beforeAction: CashTableAnimationSnapshot?,
        dealer: SeatID
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
        let awardTotals = try awardTotals(in: events)
        let lastPotAwardIndex = events.lastIndex { event in
            if case .potAwarded = event { return true }
            return false
        }

        for (eventIndex, event) in events.enumerated() {
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
            case .potAwarded:
                guard lastPotAwardIndex == eventIndex else { continue }
                for seat in orderedWinnerSeats(
                    awardTotals.keys,
                    dealer: dealer
                ) {
                    guard let amount = awardTotals[seat] else { continue }
                    mapped.append(.awardPot(seat: seat, amount: amount))
                    mapped.append(.highlightWinner(seat))
                }
            }
        }
        return mapped
    }

    private static func awardTotals(
        in events: [PublicGameEvent]
    ) throws -> [SeatID: Chips] {
        var totals: [SeatID: Chips] = [:]
        for event in events {
            guard case let .potAwarded(_, _, amounts) = event else { continue }
            for (seat, amount) in amounts {
                let current = totals[seat]?.rawValue ?? 0
                let (next, overflow) = current.addingReportingOverflow(amount.rawValue)
                guard !overflow, let total = Chips(rawValue: next) else {
                    throw PokerCoordinatorError.chipArithmeticOverflow
                }
                totals[seat] = total
            }
        }
        return totals
    }

    private static func orderedWinnerSeats(
        _ seats: Dictionary<SeatID, Chips>.Keys,
        dealer: SeatID
    ) -> [SeatID] {
        seats.sorted { left, right in
            let leftDistance = clockwiseDistance(after: dealer, to: left)
            let rightDistance = clockwiseDistance(after: dealer, to: right)
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            return left.rawValue < right.rawValue
        }
    }

    private static func clockwiseDistance(after dealer: SeatID, to seat: SeatID) -> Int {
        let distance = (seat.rawValue - dealer.rawValue + 9) % 9
        return distance == 0 ? 9 : distance
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
