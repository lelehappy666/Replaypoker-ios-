public struct EngineResult: Equatable, Sendable {
    public let state: HoldemState
    public let events: [GameEvent]

    public init(state: HoldemState, events: [GameEvent]) {
        self.state = state
        self.events = events
    }
}

public enum GameEvent: Equatable, Sendable {
    case handStarted(seed: UInt64)
    case blindPosted(seat: SeatID, amount: Chips)
    case holeCardsDealt(seat: SeatID)
    case actionApplied(seat: SeatID, action: PlayerAction)
    case streetChanged(Street)
    case communityCardsDealt([Card])
    case potCreated(Pot)
    case potAwarded(potIndex: Int, winners: [SeatID], amounts: [SeatID: Chips])
    case handCompleted
}
