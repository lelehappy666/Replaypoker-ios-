import PokerCore

package struct CashShowdownObservation: Equatable, Sendable {
    package let cardsBySeat: [SeatID: [Card]]

    package init(record: CompletedHandRecord) {
        let foldedSeats = Set(record.actions.compactMap { action in
            action.action == .fold ? action.seat : nil
        })
        cardsBySeat = record.holeCardsBySeat.filter {
            !foldedSeats.contains($0.key) && record.handRanksBySeat[$0.key] != nil
        }
    }
}
