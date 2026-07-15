import PokerCore

enum ActionCandidateKind: Equatable, Sendable {
    case fold
    case check
    case call
    case bet
    case raise
    case allIn
}

struct ActionCandidate: Equatable, Sendable {
    let kind: ActionCandidateKind
    let minimumAmount: Chips?
    let maximumAmount: Chips?

    init(
        kind: ActionCandidateKind,
        minimumAmount: Chips? = nil,
        maximumAmount: Chips? = nil
    ) {
        self.kind = kind
        self.minimumAmount = minimumAmount
        self.maximumAmount = maximumAmount
    }
}
