enum BettingActorResolver {
    static func expectedActor(in state: HoldemState) -> SeatID? {
        guard [.preflop, .flop, .turn, .river].contains(state.street) else {
            return nil
        }

        let anchor = state.actionHistory.last(where: { $0.street == state.street })?.seat
            ?? (state.street == .preflop ? state.bigBlindSeat : state.dealer)
        return circularOrder(after: anchor, among: state.seats.map(\.id)).first { id in
            guard state.canAct(id),
                  let seat = state.seats.first(where: { $0.id == id }) else {
                return false
            }
            return seat.committedThisStreet < state.currentBet
                || !state.actedSinceLastFullRaise.contains(id)
        }
    }

    private static func circularOrder(
        after anchor: SeatID,
        among ids: [SeatID]
    ) -> [SeatID] {
        ids.sorted {
            clockwiseDistance(from: anchor, to: $0)
                < clockwiseDistance(from: anchor, to: $1)
        }
    }

    private static func clockwiseDistance(from anchor: SeatID, to id: SeatID) -> Int {
        let distance = (id.rawValue - anchor.rawValue + 9) % 9
        return distance == 0 ? 9 : distance
    }
}
