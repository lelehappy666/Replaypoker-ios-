import PokerCore
import PokerSession

enum CashTableProjection {
    static func make(
        store: LocalPokerStore,
        handID: HandID,
        stateVersion: Int,
        animationSequence: Int,
        humanSeat: SeatID,
        seatProfiles: [TableSeatProfile],
        animation: TableAnimationEvent? = nil,
        secondsRemaining: Int? = nil
    ) throws -> TableViewState {
        guard let session = store.cashSession,
              let config = store.activeCashConfig,
              let spectator = store.spectatorObservation,
              let human = try store.humanObservation(),
              human.viewer == humanSeat,
              human.publicSeats == spectator.publicSeats,
              human.communityCards == spectator.communityCards,
              human.currentActor == spectator.currentActor
        else {
            throw PokerCoordinatorError.missingObservation
        }

        let profileBySeat = try validatedProfiles(
            seatProfiles,
            matching: spectator.publicSeats.map(\.id),
            humanSeat: humanSeat
        )
        guard Set(session.seats.map(\.id)) == Set(profileBySeat.keys),
              human.ownHoleCards.count == 2
        else {
            throw PokerCoordinatorError.missingObservation
        }

        let seats = try spectator.publicSeats.sorted { $0.id < $1.id }.map { seat in
            guard let profile = profileBySeat[seat.id] else {
                throw PokerCoordinatorError.missingObservation
            }
            let cards: [TableCardState]
            if seat.isSittingOut {
                cards = []
            } else if seat.id == humanSeat {
                cards = human.ownHoleCards.map(TableCardState.faceUp)
            } else {
                cards = [.faceDown, .faceDown]
            }
            return TableSeatState(
                id: seat.id,
                displayName: profile.displayName,
                isHuman: seat.id == humanSeat,
                stack: seat.stack,
                committedThisStreet: seat.committedThisStreet,
                hasFolded: seat.hasFolded,
                isAllIn: seat.isAllIn,
                isDealer: seat.id == config.dealer,
                isCurrentActor: seat.id == spectator.currentActor,
                cards: cards
            )
        }

        let pot = try checkedPot(spectator.publicSeats)
        let controls: TableActionControls?
        if spectator.currentActor == humanSeat {
            guard let legalActions = human.legalActions else {
                throw PokerCoordinatorError.missingObservation
            }
            controls = try TableActionControls(legalActions: legalActions)
        } else {
            controls = nil
        }

        return TableViewState(
            handID: handID.rawValue,
            stateVersion: stateVersion,
            animationSequence: animationSequence,
            phase: spectator.currentActor == humanSeat ? .waitingForHuman : .botThinking,
            seats: seats,
            communityCards: spectator.communityCards,
            pot: pot,
            controls: controls,
            secondsRemaining: secondsRemaining,
            winners: [],
            errorMessage: nil,
            animation: animation
        )
    }

    static func validatedProfiles(
        _ profiles: [TableSeatProfile],
        matching seats: [SeatID],
        humanSeat: SeatID
    ) throws -> [SeatID: TableSeatProfile] {
        guard profiles.count == 9,
              Set(profiles.map(\.id)).count == 9,
              Set(profiles.map(\.displayName)).count == 9,
              Set(profiles.map(\.id)) == Set(seats),
              profiles.contains(where: { $0.id == humanSeat })
        else {
            throw PokerCoordinatorError.missingObservation
        }
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    private static func checkedPot(_ seats: [PublicSeat]) throws -> Chips {
        var total = 0
        for seat in seats {
            let (next, overflow) = total.addingReportingOverflow(
                seat.committedThisHand.rawValue
            )
            guard !overflow else {
                throw PokerCoordinatorError.chipArithmeticOverflow
            }
            total = next
        }
        guard let pot = Chips(rawValue: total) else {
            throw PokerCoordinatorError.chipArithmeticOverflow
        }
        return pot
    }
}
