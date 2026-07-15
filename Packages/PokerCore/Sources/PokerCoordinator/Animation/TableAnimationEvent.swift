import PokerCore

public enum TableAnimationKind: String, Codable, Equatable, Sendable {
    case dealHoleCard
    case postBlind
    case showAction
    case moveCommitmentToPot
    case streetChanged
    case revealCommunityCard
    case returnUncalledBet
    case awardPot
    case highlightWinner
}

public enum TableAnimationEvent: Codable, Equatable, Sendable {
    case dealHoleCard(seat: SeatID, card: TableCardState)
    case postBlind(seat: SeatID, amount: Chips)
    case showAction(seat: SeatID, action: PlayerAction)
    case moveCommitmentToPot(seat: SeatID, amount: Chips)
    case streetChanged(Street)
    case revealCommunityCard(card: Card, index: Int)
    case returnUncalledBet(seat: SeatID, amount: Chips)
    case awardPot(seat: SeatID, amount: Chips, potIndex: Int)
    case highlightWinner(SeatID)

    public var kind: TableAnimationKind {
        switch self {
        case .dealHoleCard: .dealHoleCard
        case .postBlind: .postBlind
        case .showAction: .showAction
        case .moveCommitmentToPot: .moveCommitmentToPot
        case .streetChanged: .streetChanged
        case .revealCommunityCard: .revealCommunityCard
        case .returnUncalledBet: .returnUncalledBet
        case .awardPot: .awardPot
        case .highlightWinner: .highlightWinner
        }
    }
}
