import PokerCore

public enum TableIntent: Equatable, Sendable {
    case fold
    case middle
    case aggressive(amount: Chips)
    case nextHand
    case retrySave
}
